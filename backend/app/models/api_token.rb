require 'digest'
require 'securerandom'

# Per-caller bearer token for the machine-callable registration API
# (app/controllers/v1/datasets_controller.rb).
#
# Ported from legacy production SUSHI (uzh/sushi) design v0.7. Secrecy at rest:
# only a salted SHA-256 hash of the raw token is stored; the raw token is shown
# exactly once at issue time and never persisted.
#
# A token has exactly one principal:
#   - `static`: authorized against the stored project-number array (`scope`),
#     frozen at issue. Used by the /v1 registration API.
#   - `user`: bound to a non-blank LDAP `login` and a mandatory bounded TTL;
#     authorized live, per request, against the login's current FGCZ project
#     membership (no cache, W=0). `scope` is unused.
#   - `machine`: an unscoped infrastructure credential for the /internal bridge
#     (job_manager / GeoUploader), which operates system-wide. Kept DISTINCT from
#     `static` on purpose: a project-scoped registration token must NOT also grant
#     system-wide internal-bridge access. The /internal surface requires `machine`;
#     the /v1 surface rejects it.
class ApiToken < ActiveRecord::Base
  serialize :scope, type: Array, coder: YAML
  serialize :capabilities, type: Array, coder: YAML

  # Mandatory upper bound on a `user` token's lifetime (design v0.7 P-INV-10).
  MAX_USER_TOKEN_TTL_DAYS = 90

  # Write authority, orthogonal to project scope. Scope answers "which projects";
  # this answers "may it change anything there at all".
  #
  # FAIL-CLOSED: a token with no capabilities recorded (every token issued before
  # this column existed) is READ-ONLY. That is deliberate — the production node is
  # only safe today because the whole instance is server-side read-only, and
  # flipping SUSHI_WRITE_POLICY to `additive` would otherwise silently promote the
  # read-only MCP credential into a job submitter. Grant write explicitly.
  CAPABILITIES = %w[read write].freeze
  DEFAULT_CAPABILITIES = %w[read].freeze

  # Write authority for an ENV-provisioned credential, which has NO row to record
  # capabilities in — and, on the production node, no `capabilities` column either
  # (assigning it there raises ActiveModel::UnknownAttributeError, and
  # #effective_capabilities fail-closes to read-only regardless). So the WRITE
  # credential's authority travels on this non-database channel instead.
  #
  # Granted ONLY by EnvApiToken#build, for the separate write credential
  # (SUSHI_ENV_TOKEN_WRITE_*).
  #
  # Deliberately a no-argument bang method rather than an `attr_writer` (multi-LLM
  # review round 1, P3): there is no value to get wrong, so a truthy-but-not-true
  # assignment cannot promote a token, and — because it is not a writer and not a
  # database attribute — an attributes hash carrying `env_write_granted: true`
  # RAISES ActiveModel::UnknownAttributeError instead of quietly doing nothing.
  # Fail-closed default: unset ⇒ read-only.
  #
  # REFUSES a persisted record (review round 2, P3, cited by two reviewers). The
  # method has to stay public for EnvApiToken to call it, so "only EnvApiToken
  # grants this" was a claim about call sites rather than about the code. Blocking
  # persisted records makes the dangerous half of that claim structural instead:
  # a row loaded from `api_tokens` — where authority belongs to `capabilities`
  # alone — can never be promoted through this channel by any in-process caller.
  # Private + `send` was the alternative and would only have added obscurity while
  # leaving the DB case reachable.
  def grant_env_write!
    if persisted?
      raise ArgumentError,
            "env write authority is only for the ENV-provisioned credential, which " \
            "is never saved; a persisted ApiToken's write authority comes from its " \
            "capabilities column"
    end

    @env_write_granted = true
  end

  def env_write_granted?
    @env_write_granted == true
  end

  # Raised when the live project-membership resolver cannot answer (transport
  # failure). The controller maps this to 503, distinct from an authorization
  # denial (403). Fail-closed: the request never proceeds.
  class ResolverUnavailable < StandardError; end

  # Salt the hash with the app's secret_key_base so a leaked api_tokens table
  # is not directly reversible without the server secret.
  def self.salt
    Rails.application.secret_key_base.to_s
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(salt + raw.to_s)
  end

  # Issue a new token. Returns [raw_token, record]. The raw value cannot be
  # recovered afterwards.
  #
  # principal: "static" (default) requires a non-empty scope; "user" requires a
  # non-blank login and a TTL within MAX_USER_TOKEN_TTL_DAYS (scope is ignored).
  #
  # capabilities: subset of CAPABILITIES. Omitted ⇒ read-only (see CAPABILITIES).
  def self.issue(name:, scope: [], ttl_days: nil, principal: "static", login: nil,
                 capabilities: nil)
    caps = normalize_capabilities(capabilities)
    principal = principal.to_s
    case principal
    when "user"
      raise ArgumentError, "login is required for a user token" if login.to_s.strip.empty?
      ttl_raw = ttl_days.to_s.strip
      raise ArgumentError, "a user token requires TTL_DAYS (mandatory bounded TTL)" if ttl_raw.empty?
      # Strict integer: reject "90abc"/"90.9" rather than silently truncating.
      raise ArgumentError, "TTL_DAYS must be a positive integer" unless ttl_raw.match?(/\A\d+\z/)
      ttl_days = ttl_raw.to_i
      if ttl_days <= 0 || ttl_days > MAX_USER_TOKEN_TTL_DAYS
        raise ArgumentError, "TTL_DAYS must be between 1 and #{MAX_USER_TOKEN_TTL_DAYS} for a user token"
      end
      scope = []
    when "static"
      # A static token authorizes only its explicit scope; an empty scope would
      # authorize nothing, so require it (the `scope:` default exists for the
      # user branch, which ignores scope).
      if Array(scope).map { |x| x.to_s.strip }.reject(&:empty?).empty?
        raise ArgumentError, "scope is required for a static token"
      end
    when "machine"
      # An infra credential for the /internal bridge: no project scope (it acts
      # system-wide) and no login. TTL is optional (long-lived infra secret).
      scope = []
    else
      raise ArgumentError, "unknown principal #{principal.inspect} (expected static|user|machine)"
    end

    raw = SecureRandom.urlsafe_base64(32)
    record = create!(
      name:         name,
      token_hash:   digest(raw),
      scope:        Array(scope).map(&:to_i),
      principal:    principal,
      login:        (principal == "user" ? login.to_s.strip : nil),
      capabilities: caps,
      expires_at:   ttl_days ? Time.now + ttl_days.to_i.days : nil
    )
    [raw, record]
  end

  # Unknown names are rejected rather than ignored, so a typo ("wirte") cannot
  # quietly produce a token that is not what the operator asked for.
  def self.normalize_capabilities(list)
    caps = Array(list).map { |c| c.to_s.strip.downcase }.reject(&:empty?).uniq
    return DEFAULT_CAPABILITIES.dup if caps.empty?

    unknown = caps - CAPABILITIES
    raise ArgumentError, "unknown capabilities #{unknown.inspect} (expected #{CAPABILITIES.join('|')})" if unknown.any?

    # "write" without "read" would be a token that can change what it cannot see.
    caps |= DEFAULT_CAPABILITIES
    caps
  end

  # Look up an active token by its raw value. Fail-closed: returns nil for any
  # missing/unknown/expired/revoked token.
  #
  # DB first; the ENV-provisioned credential (EnvApiToken) is a strictly ADDITIVE
  # fallback, tried only on a DB miss. Two consequences worth stating:
  #   - a row that exists but is expired or revoked stays denied — the ENV path
  #     can never resurrect it;
  #   - a node that configures no ENV credential behaves exactly as it did before
  #     this path existed.
  # Every surface authenticates through this one method (/api/v1 via
  # ApiTokenAuthenticatable, /v1 via V1::DatasetsController#require_bearer_token,
  # /internal via Internal::LegacyController#require_machine_token), so the ENV
  # credential is available — and equally constrained — on all of them.
  def self.authenticate(raw)
    return nil if raw.to_s.empty?

    token = find_by(token_hash: digest(raw))
    return token if token&.active?

    # The ENV credential is consulted ONLY on a DB miss. A row that exists but is
    # expired or revoked must stay denied, so it never reaches this branch — but
    # it does still fall through to the log below, because a withdrawn credential
    # being presented over and over is exactly the event worth seeing.
    if token.nil?
      env = EnvApiToken.token_for(raw)
      return env if env
    end

    log_failed_bearer_attempt
    nil
  end

  # A failed bearer attempt used to be completely silent, so a probing client or a
  # client still using a revoked token left no evidence at all. Keyed on
  # `intended?` (any of the ENV variables set) rather than `enabled?`, because a
  # misconfiguration is precisely the case where the silence was most misleading —
  # and keyed on the ENV credential at all so that no node's log volume changes
  # without opting in. Never logs the token or its digest; this seam has no
  # request context to log.
  def self.log_failed_bearer_attempt
    return unless EnvApiToken.intended?

    Rails.logger.warn(
      "ApiToken: bearer authentication failed (no active row, no ENV credential match)"
    )
  end
  private_class_method :log_failed_bearer_attempt

  def user?
    principal.to_s == "user"
  end

  def static?
    principal.to_s == "static"
  end

  def machine?
    principal.to_s == "machine"
  end

  # True when the backing column has actually been added to the connected database.
  #
  # This is not paranoia: New SUSHI runs against the legacy `sushi` schema, whose
  # migration history is managed out-of-band (api_tokens itself is marked `down`
  # while existing, and some applied migrations have no file). A deploy that skips
  # the ALTER TABLE therefore silently fail-closes every token to read-only, which
  # looks like a mysterious 403 rather than a missing column. Say so instead.
  def self.capabilities_column_present?
    column_names.include?("capabilities")
  rescue ActiveRecord::ActiveRecordError
    false
  end

  # Recorded capabilities, or the fail-closed default for a token issued before
  # the column existed (NULL ⇒ read-only).
  def effective_capabilities
    unless self.class.capabilities_column_present?
      Rails.logger.warn(
        "ApiToken#capabilities column is MISSING in this database; every token is " \
        "treated as read-only. Run the AddCapabilitiesToApiTokens migration (or the " \
        "equivalent ALTER TABLE) against this DB."
      )
      return DEFAULT_CAPABILITIES.dup
    end

    caps = Array(capabilities).map { |c| c.to_s.strip.downcase }.reject(&:empty?)
    caps.empty? ? DEFAULT_CAPABILITIES.dup : caps
  end

  # May this token change anything? The /internal bridge credential is exempt:
  # it is the job_manager advancing job state, which the write policy also
  # exempts, and it has no project scope to gate on.
  def can_write?
    return true if machine?
    # The ENV-provisioned WRITE credential: no row, and on the production node no
    # `capabilities` column to read, so its authority cannot come from
    # #effective_capabilities. See EnvApiToken.
    return true if env_write_granted?

    effective_capabilities.include?("write")
  end

  # Operator guidance for a 403 from the write gate. The two surfaces share it so
  # they cannot drift apart.
  #
  # An ENV-provisioned credential has no row and therefore no id, so pointing its
  # holder at `grant_write ID=` would send them looking for a record that does not
  # exist — on the production node, where nothing may be written to `api_tokens`
  # anyway. Say what is actually true instead.
  #
  # Only the READ credential can reach this branch: the write credential's
  # #can_write? is true, so it is never denied here.
  def write_denied_message
    if persisted?
      "This token is read-only. Grant write authority explicitly " \
      "(rake api_token:grant_write ID=#{id}) or use a token that has it."
    else
      "This token is read-only. It is the ENV-provisioned READ credential " \
      "(#{EnvApiToken::NAME_VAR}) and is read-only by construction. Write " \
      "authority belongs to a SEPARATE credential " \
      "(#{EnvApiToken::WRITE_DIGEST_VAR}), which is a different bearer value — " \
      "this one cannot be promoted."
    end
  end

  def active?
    return false if revoked? || expired?
    # A user token's TTL is mandatory; a null expiry must never authenticate
    # (defense in depth — issuance already enforces this). Design v0.7 step 2.
    return false if user? && expires_at.nil?
    true
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.now
  end

  # Static-principal membership test (unchanged). Not used for `user` tokens;
  # user membership is tested against the live-resolved set (see allowed_projects).
  def in_scope?(project_number)
    Array(scope).map(&:to_i).include?(project_number.to_i)
  end

  # The set of project numbers this token may currently act on.
  #   - static: the stored scope array.
  #   - user:   the login's current FGCZ project membership, resolved live
  #             (W=0). An inactive/unknown login yields the empty set (→ 403).
  #
  # Raises ResolverUnavailable when the resolver *call* fails (→ 503). The rescue
  # is scoped to the resolver call alone so parsing bugs are NOT masked as
  # infrastructure errors.
  def allowed_projects
    return Array(scope).map(&:to_i) unless user?

    raw =
      begin
        FGCZ.get_user_projects2(login)
      rescue => e
        raise ResolverUnavailable, "#{e.class}: #{e.message}"
      end

    Array(raw).map { |p| p.to_s.sub(/\Ap/i, "").to_i }.select(&:positive?)
  end
end
