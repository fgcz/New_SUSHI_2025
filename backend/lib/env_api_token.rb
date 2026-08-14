# frozen_string_literal: true

require "digest"
require "active_support/security_utils"

# DB-free bearer credentials, configured entirely through the process environment
# and parsed exactly ONCE per process.
#
# Why they exist: on the FGCZ production node, `api_tokens` is LEGACY production
# SUSHI's own table — it holds real users' registration tokens, and New SUSHI's
# ApiToken is a faithful port that merely shares it. Issuing a token there means
# INSERTing into a table another live application owns, and the operator has
# forbidden any write or schema change on that database. Meanwhile
# SUSHI_REQUIRE_AUTH=1 (deliberately) admits no anonymous access. Without a
# DB-free credential that node cannot serve an authenticated read at all.
#
# TWO credentials, deliberately separate (082 cutover route B'):
#
#   READ  (SUSHI_ENV_TOKEN_{SHA256,SCOPE,NAME})       — read-only by construction
#   WRITE (SUSHI_ENV_TOKEN_WRITE_{SHA256,SCOPE,NAME}) — may CREATE, opt-in
#
# The read credential is what MCP `prod-082` / sushi-chain presents, i.e. what an
# agent uses to read production. Promoting that same bearer value to a writer
# would mean routine agent traffic can create production rows for as long as the
# cutover window is open. Keeping them separate makes "the MCP key cannot write
# production" permanently true, and gives production rows a distinct
# `apitoken:<name>` attribution — the only audit trail a DB-free credential has.
# The two must therefore differ in BOTH digest and name; conflating them is a
# hard configuration error, not a silent upgrade of the read credential.
#
# Deliberately NOT autoloaded — see the `autoload_lib(ignore:)` list in
# config/application.rb, which requires this file at boot instead. Under Rails'
# development reloader an autoloaded constant is discarded between requests,
# which would re-read ENV; the production node runs in DEVELOPMENT mode, so
# "frozen once per process" would otherwise be a claim that quietly failed
# exactly where it matters.
#
# The environment holds the SHA-256 DIGEST of each token, never the raw value: a
# leaked /proc/<pid>/environ, `ps e` output or shell-history line then yields
# nothing usable.
#
# HOW WRITE AUTHORITY TRAVELS. Not through `capabilities`: on the production node
# that column does not exist, so assigning it raises
# ActiveModel::UnknownAttributeError, and ApiToken#effective_capabilities
# fail-closes to ["read"] there regardless of what was assigned. The write
# credential therefore sets ApiToken#env_write_granted, a non-database channel
# that exists for exactly this case. Neither credential is ever saved.
#
# The Rack write policy (Middleware::SushiReadOnlyGuard) is a SEPARATE gate. A
# write credential alone cannot write: SUSHI_WRITE_POLICY must also permit the
# route. Both gates must be open, by design.
module EnvApiToken
  DIGEST_VAR = "SUSHI_ENV_TOKEN_SHA256"
  SCOPE_VAR  = "SUSHI_ENV_TOKEN_SCOPE"
  NAME_VAR   = "SUSHI_ENV_TOKEN_NAME"
  READ_VARS  = [DIGEST_VAR, SCOPE_VAR, NAME_VAR].freeze

  WRITE_DIGEST_VAR = "SUSHI_ENV_TOKEN_WRITE_SHA256"
  WRITE_SCOPE_VAR  = "SUSHI_ENV_TOKEN_WRITE_SCOPE"
  WRITE_NAME_VAR   = "SUSHI_ENV_TOKEN_WRITE_NAME"
  WRITE_VARS = [WRITE_DIGEST_VAR, WRITE_SCOPE_VAR, WRITE_NAME_VAR].freeze

  VARS = (READ_VARS + WRITE_VARS).freeze

  SHA256_HEX = /\A[0-9a-f]{64}\z/
  POSITIVE_INTEGER = /\A\d+\z/

  # The name is not free text. It is interpolated into a log line and into the
  # synthetic login `apitoken:<name>`, and the provisioning rake task prints it
  # inside a copy-pasteable `export`. Restricting the charset closes log
  # injection (a newline would forge a log record) and shell injection at the
  # source, rather than escaping the same value in three places.
  NAME_FORMAT = /\A[A-Za-z0-9._-]{1,64}\z/

  Config = Struct.new(:digest, :scope, :name)

  class << self
    # The frozen READ credential, or nil when none is configured or the
    # configuration is invalid. Parsed on first call;
    # config/initializers/env_api_token.rb forces that call during boot so
    # authority is fixed before the first request is served.
    def config
      parse! unless defined?(@config)
      @config
    end

    # The frozen WRITE credential, or nil. Same lifecycle as #config.
    def write_config
      parse! unless defined?(@write_config)
      @write_config
    end

    # Validation messages from the parse, for both credentials. Empty when each is
    # either fully valid or entirely absent.
    def errors
      parse! unless defined?(@errors)
      @errors
    end

    def enabled?
      !config.nil?
    end

    def write_enabled?
      !write_config.nil?
    end

    # True when the operator set ANY of the six variables — i.e. INTENDED to
    # configure a credential, whether or not they got it right. Keying the
    # failed-authentication log line on `enabled?` instead would go silent again
    # in precisely the misconfigured case where the evidence is most needed.
    def intended?
      VARS.any? { |v| ENV[v].to_s.strip != "" }
    end

    # Authenticate a raw bearer value against the configured digests.
    #
    # Returns an UNSAVED ApiToken — nothing may be written to a database we do
    # not own — or nil. Comparison is constant-time over fixed-length hex digests.
    #
    # The READ credential is tried first. Since the two digests are required to
    # differ, the order cannot mask a write credential; it only means that a
    # configuration which somehow presented both would resolve to the LESSER
    # authority.
    def token_for(raw)
      return nil if raw.to_s.empty?

      presented = Digest::SHA256.hexdigest(raw.to_s)

      if (cfg = config) && digest_match?(presented, cfg.digest)
        return build(cfg, write: false)
      end

      if (cfg = write_config) && digest_match?(presented, cfg.digest)
        return build(cfg, write: true)
      end

      nil
    end

    # Digest of a raw token, in the form the DIGEST vars expect. Shared by the
    # rake task so the two can never disagree about the algorithm.
    def digest_of(raw)
      Digest::SHA256.hexdigest(raw.to_s)
    end

    # Specs only: they must be able to vary ENV between examples. Guarded rather
    # than merely documented, so production code cannot re-read ENV mid-process
    # by accident and undo the freeze.
    def reload!
      raise "EnvApiToken.reload! is test-only" unless defined?(Rails) && Rails.env.test?

      remove_instance_variable(:@config) if defined?(@config)
      remove_instance_variable(:@write_config) if defined?(@write_config)
      remove_instance_variable(:@errors) if defined?(@errors)
      config
    end

    private

    def digest_match?(presented, configured)
      ActiveSupport::SecurityUtils.secure_compare(presented, configured)
    end

    # `capabilities` is deliberately never assigned: that is what keeps this line
    # working on the production node, where the column does not exist at all
    # (assigning it would raise ActiveModel::UnknownAttributeError). Write
    # authority rides the non-database `env_write_granted` channel instead.
    #
    # The frozen scope is passed as-is rather than duplicated, so no caller can
    # widen a credential's authority in place. Readers (`in_scope?`,
    # `allowed_projects`) build new arrays, so they are unaffected.
    def build(cfg, write:)
      token = ApiToken.new(name: cfg.name, principal: "static", scope: cfg.scope)
      token.grant_env_write! if write
      token
    end

    def parse!
      read_errors, read_config = parse_credential(DIGEST_VAR, SCOPE_VAR, NAME_VAR)
      write_errors, write_config = parse_credential(WRITE_DIGEST_VAR, WRITE_SCOPE_VAR, WRITE_NAME_VAR)

      write_errors += collision_errors
      write_config = nil if write_errors.any?

      @config = read_config
      @write_config = write_config
      @errors = (read_errors + write_errors).freeze
    end

    # Collisions between the two credentials, compared on the RAW ENV values.
    #
    # These used to be compared on the PARSED configs, which meant the check ran
    # only when BOTH credentials parsed successfully (multi-LLM review round 1,
    # P1, cited independently by two reviewers). An operator who typo'd the READ
    # scope while reusing the read digest as the write digest then got no
    # collision error at all — and the bearer value an agent already holds became
    # a writer. That is one typo in a launch script away from precisely the
    # outcome this two-credential design exists to prevent.
    #
    # Whether two configured values collide has nothing to do with whether either
    # credential parsed, so parse success must not gate the comparison. Plain ==
    # is right here: this is boot-time operator configuration, not a
    # timing-sensitive comparison against a presented secret.
    def collision_errors
      errors = []
      read_digest  = ENV[DIGEST_VAR].to_s.strip
      write_digest = ENV[WRITE_DIGEST_VAR].to_s.strip
      read_name    = ENV[NAME_VAR].to_s.strip
      write_name   = ENV[WRITE_NAME_VAR].to_s.strip

      if !read_digest.empty? && read_digest == write_digest
        errors << "#{WRITE_DIGEST_VAR} must differ from #{DIGEST_VAR}: the read and " \
                  "write credentials must be different bearer values, or the read " \
                  "credential would silently become a writer"
      end

      if !read_name.empty? && read_name == write_name
        errors << "#{WRITE_NAME_VAR} must differ from #{NAME_VAR}: the name is the " \
                  "only attribution a production row carries (apitoken:<name>), so " \
                  "sharing it would make read traffic and a write run " \
                  "indistinguishable afterwards"
      end

      errors
    end

    # Parse one credential from its three variables.
    # @return [Array(Array<String>, Config|nil)] errors and the frozen config
    def parse_credential(digest_var, scope_var, name_var)
      digest_hex = ENV[digest_var].to_s.strip
      scope_raw  = ENV[scope_var].to_s.strip
      name       = ENV[name_var].to_s.strip

      # Nothing set at all: the normal case on every node that does not use this,
      # and the normal case for the WRITE credential on every node but during a
      # deliberate cutover window.
      return [[], nil] if digest_hex.empty? && scope_raw.empty? && name.empty?

      errors = []
      unless digest_hex.match?(SHA256_HEX)
        errors << "#{digest_var} must be a 64-character lowercase hex SHA-256 digest"
      end

      # Every field must be a positive integer. This used to check the FORMAT of
      # every field and then `select(&:positive?)`, which silently DROPPED a zero:
      # "0,1" quietly became scope [1] instead of being refused (multi-LLM review
      # round 1, P2 — pre-existing, not introduced with the write credential). A
      # scope is authority, so narrowing it silently is the wrong direction for a
      # parser whose whole job is to fail closed.
      # Empty fields are refused rather than dropped too (review round 2, P2), so
      # "1,,2" and ",1" are malformed instead of quietly meaning [1, 2] and [1].
      # Same reasoning as the zero: an authority list should be parsed strictly or
      # not at all. Surrounding whitespace is still tolerated ("35611, 1001").
      fields = scope_raw.split(",", -1).map(&:strip)
      all_positive = fields.any? && fields.all? do |f|
        f.match?(POSITIVE_INTEGER) && f.to_i.positive?
      end
      scope = all_positive ? fields.map(&:to_i) : []
      if scope.empty?
        errors << "#{scope_var} must be a comma-separated list of positive project numbers"
      end

      unless name.match?(NAME_FORMAT)
        errors << "#{name_var} must be 1-64 characters of [A-Za-z0-9._-] " \
                  "(it appears in log lines and in the attributed login)"
      end

      config =
        if errors.empty?
          Config.new(digest_hex.dup.freeze, scope.freeze, name.dup.freeze).freeze
        end

      [errors, config]
    end
  end
end
