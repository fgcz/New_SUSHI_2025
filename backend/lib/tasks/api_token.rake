namespace :api_token do
  # Interim admin flow to mint a registration-API token. The raw token is
  # printed ONCE; only its salted hash is stored.
  #
  # static (default): scope is a fixed list of project numbers.
  #   rake api_token:issue NAME=registrar-test SCOPE=2680,3186 TTL_DAYS=90
  # user: bound to an LDAP login; authorized live against that login's current
  # FGCZ project membership. login + a bounded TTL are mandatory; SCOPE ignored.
  #   rake api_token:issue PRINCIPAL=user NAME=hubert-reg LOGIN=hubert TTL_DAYS=90
  # machine: unscoped infra credential for the /internal bridge (job_manager /
  # GeoUploader). No SCOPE, no LOGIN; TTL optional.
  #   rake api_token:issue PRINCIPAL=machine NAME=job_manager
  # CAPABILITIES defaults to read-only. Pass CAPABILITIES=read,write for a token
  # that may submit jobs or import datasets:
  #   rake api_token:issue PRINCIPAL=user NAME=hubert-submit LOGIN=hubert TTL_DAYS=90 CAPABILITIES=read,write
  desc "Issue an API token (NAME=, PRINCIPAL=static|user|machine, SCOPE=comma,projects (static), LOGIN= (user), TTL_DAYS=, CAPABILITIES=read[,write])"
  task issue: :environment do
    name      = ENV["NAME"] or abort("NAME is required")
    principal = (ENV["PRINCIPAL"] || "static").strip
    ttl       = ENV["TTL_DAYS"]
    caps      = ENV["CAPABILITIES"].to_s.split(",").map(&:strip).reject(&:empty?)

    begin
      case principal
      when "user"
        raw, record = ApiToken.issue(name: name, ttl_days: ttl, capabilities: caps,
                                     principal: "user", login: ENV["LOGIN"])
      when "machine"
        raw, record = ApiToken.issue(name: name, principal: "machine", ttl_days: ttl,
                                     capabilities: caps)
      else
        scope = ENV["SCOPE"].to_s.split(",").map(&:strip).reject(&:empty?).map(&:to_i)
        abort("SCOPE is required (comma-separated project numbers)") if scope.empty?
        raw, record = ApiToken.issue(name: name, scope: scope, ttl_days: ttl,
                                     capabilities: caps)
      end
    rescue ArgumentError => e
      abort("cannot issue token: #{e.message}")
    end

    detail = record.user? ? "login=#{record.login}" : "scope=#{record.scope.inspect}"
    puts "Issued API token id=#{record.id} name=#{record.name} principal=#{record.principal} " \
         "#{detail} capabilities=#{record.effective_capabilities.inspect} " \
         "expires_at=#{record.expires_at || 'never'}"
    puts "RAW TOKEN (shown once, store securely):"
    puts raw
  end

  # Changes authority WITHOUT reissuing, so a wired-up client (e.g. .mcp.json)
  # keeps working — the raw token and its hash are untouched.
  desc "Grant write authority to an existing API token (ID=)"
  task grant_write: :environment do
    id = ENV["ID"] or abort("ID is required")
    token = ApiToken.find(id)
    token.update!(capabilities: ApiToken.normalize_capabilities(%w[read write]))
    puts "API token id=#{token.id} name=#{token.name} capabilities=#{token.effective_capabilities.inspect}"
  end

  desc "Revoke write authority from an existing API token, leaving it read-only (ID=)"
  task revoke_write: :environment do
    id = ENV["ID"] or abort("ID is required")
    token = ApiToken.find(id)
    token.update!(capabilities: ApiToken::DEFAULT_CAPABILITIES.dup)
    puts "API token id=#{token.id} name=#{token.name} capabilities=#{token.effective_capabilities.inspect}"
  end

  desc "List API tokens with principal / scope / capabilities (no secrets)"
  task list: :environment do
    ApiToken.order(:id).each do |t|
      state = t.revoked? ? "REVOKED" : (t.expired? ? "EXPIRED" : "active")
      detail = t.user? ? "login=#{t.login}" : "scope=#{t.scope.inspect}"
      puts format("id=%-4s %-9s %-8s %-28s caps=%-16s %s name=%s",
                  t.id, state, t.principal, detail,
                  t.effective_capabilities.join(","), t.expires_at || "never", t.name)
    end
  end

  desc "Revoke an API token by id (ID=)"
  task revoke: :environment do
    id = ENV["ID"] or abort("ID is required")
    token = ApiToken.find(id)
    token.update!(revoked_at: Time.now)
    puts "Revoked API token id=#{token.id} name=#{token.name}"
  end

  # Mint a credential for the ENV-provisioned principal (see lib/env_api_token.rb).
  #
  # Note the DELIBERATE absence of `:environment`: this task never loads Rails and
  # never opens a database connection. That is the whole point — it is the way to
  # provision a credential for the production node, whose `api_tokens` table
  # belongs to legacy SUSHI and must be neither written nor altered.
  #
  # The raw token is printed once and stored nowhere; only its digest goes into
  # the node's launch script.
  desc "Generate an ENV-provisioned API token credential (NAME=, SCOPE=comma,projects, WRITE=1 for the separate write credential) — no DB access"
  task :env_token do
    require "digest"
    require "securerandom"
    require_relative "../env_api_token"

    name  = ENV["NAME"].to_s.strip
    scope = ENV["SCOPE"].to_s.split(",").map(&:strip).reject(&:empty?)
    abort("NAME is required") if name.empty?
    # Same charset the server enforces, so a name accepted here can never be
    # rejected at boot — and so the `export` line printed below cannot carry a
    # newline or a shell metacharacter into the operator's paste buffer.
    unless name.match?(EnvApiToken::NAME_FORMAT)
      abort("NAME must be 1-64 characters of [A-Za-z0-9._-]")
    end
    abort("SCOPE is required (comma-separated project numbers)") if scope.empty?
    unless scope.all? { |s| s.match?(/\A\d+\z/) && s.to_i.positive? }
      abort("SCOPE must contain only positive integers")
    end

    # WRITE=1 provisions the SEPARATE write credential instead of the read one.
    # Two credentials rather than one flag: see the header of lib/env_api_token.rb.
    write = %w[1 true yes].include?(ENV["WRITE"].to_s.strip.downcase)

    raw = SecureRandom.urlsafe_base64(32)

    puts "RAW TOKEN (shown once, stored nowhere — this is the bearer value clients send):"
    puts raw
    puts
    puts "Add to the node's launch script. The server keeps only the DIGEST:"
    if write
      puts "export #{EnvApiToken::WRITE_DIGEST_VAR}=#{EnvApiToken.digest_of(raw)}"
      puts "export #{EnvApiToken::WRITE_SCOPE_VAR}=#{scope.join(',')}"
      puts "export #{EnvApiToken::WRITE_NAME_VAR}=#{name}"
      puts
      puts "This is the WRITE credential. It may CREATE rows (job submit, dataset import)."
      puts "It must differ from the read credential in BOTH digest and NAME, or the server"
      puts "refuses it at boot. Two further facts worth keeping in mind:"
      puts "  - the Rack write policy is a SEPARATE gate: SUSHI_WRITE_POLICY must also"
      puts "    permit the route, so this alone does not make the node writable;"
      puts "  - the name is the only audit trail — production rows will be attributed to"
      puts "    apitoken:#{name}."
    else
      puts "export #{EnvApiToken::DIGEST_VAR}=#{EnvApiToken.digest_of(raw)}"
      puts "export #{EnvApiToken::SCOPE_VAR}=#{scope.join(',')}"
      puts "export #{EnvApiToken::NAME_VAR}=#{name}"
      puts
      puts "The credential is READ-ONLY by construction (static principal, no capabilities),"
      puts "and is rejected by the /internal machine bridge. For a credential that may"
      puts "write, provision a separate one with WRITE=1 — never reuse this bearer value."
    end
  end
end
