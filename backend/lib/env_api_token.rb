# frozen_string_literal: true

require "digest"
require "active_support/security_utils"

# A DB-free bearer credential, configured entirely through the process
# environment and parsed exactly ONCE per process.
#
# Why it exists: on the FGCZ production node, `api_tokens` is LEGACY production
# SUSHI's own table — it holds real users' registration tokens, and New SUSHI's
# ApiToken is a faithful port that merely shares it. Issuing a token there means
# INSERTing into a table another live application owns, and the operator has
# forbidden any write or schema change on that database. Meanwhile
# SUSHI_REQUIRE_AUTH=1 (deliberately) admits no anonymous access. Without a
# DB-free credential that node cannot serve an authenticated read at all.
#
# Deliberately NOT autoloaded — see the `autoload_lib(ignore:)` list in
# config/application.rb, which requires this file at boot instead. Under Rails'
# development reloader an autoloaded constant is discarded between requests,
# which would re-read ENV; the production node runs in DEVELOPMENT mode, so
# "frozen once per process" would otherwise be a claim that quietly failed
# exactly where it matters.
#
# The environment holds the SHA-256 DIGEST of the token, never the raw value: a
# leaked /proc/<pid>/environ, `ps e` output or shell-history line then yields
# nothing usable.
#
# READ-ONLY BY CONSTRUCTION. The credential materializes as an ApiToken with a
# `static` principal and no `capabilities` assigned, so
# ApiToken#effective_capabilities fail-closes to ["read"] on any schema and
# #can_write? is false.
# Write authority cannot be granted here through configuration alone; it would
# take a deliberate, reviewed code change.
module EnvApiToken
  DIGEST_VAR = "SUSHI_ENV_TOKEN_SHA256"
  SCOPE_VAR  = "SUSHI_ENV_TOKEN_SCOPE"
  NAME_VAR   = "SUSHI_ENV_TOKEN_NAME"
  VARS = [DIGEST_VAR, SCOPE_VAR, NAME_VAR].freeze

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
    # The frozen credential, or nil when none is configured or the configuration
    # is invalid. Parsed on first call; config/initializers/env_api_token.rb
    # forces that call during boot so authority is fixed before the first request
    # is served.
    def config
      parse! unless defined?(@config)
      @config
    end

    # Validation messages from the parse. Empty when the credential is either
    # fully valid or entirely absent.
    def errors
      parse! unless defined?(@errors)
      @errors
    end

    def enabled?
      !config.nil?
    end

    # True when the operator set ANY of the three variables — i.e. INTENDED to
    # configure the credential, whether or not they got it right. Keying the
    # failed-authentication log line on `enabled?` instead would go silent again
    # in precisely the misconfigured case where the evidence is most needed.
    def intended?
      VARS.any? { |v| ENV[v].to_s.strip != "" }
    end

    # Authenticate a raw bearer value against the configured digest.
    #
    # Returns an UNSAVED ApiToken — nothing may be written to a database we do
    # not own — or nil. Comparison is constant-time over two fixed-length hex
    # digests.
    def token_for(raw)
      cfg = config
      return nil if cfg.nil?
      return nil if raw.to_s.empty?

      presented = Digest::SHA256.hexdigest(raw.to_s)
      return nil unless ActiveSupport::SecurityUtils.secure_compare(presented, cfg.digest)

      # `capabilities` is deliberately never assigned: that is what makes the
      # credential read-only on every schema, and it is also what keeps this line
      # working on the production node, where the column does not exist at all
      # (assigning it would raise ActiveModel::UnknownAttributeError).
      #
      # The frozen scope is passed as-is rather than duplicated, so no caller can
      # widen this credential's authority in place. Readers (`in_scope?`,
      # `allowed_projects`) build new arrays, so they are unaffected.
      ApiToken.new(name: cfg.name, principal: "static", scope: cfg.scope)
    end

    # Digest of a raw token, in the form the DIGEST_VAR expects. Shared by the
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
      remove_instance_variable(:@errors) if defined?(@errors)
      config
    end

    private

    def parse!
      digest_hex = ENV[DIGEST_VAR].to_s.strip
      scope_raw  = ENV[SCOPE_VAR].to_s.strip
      name       = ENV[NAME_VAR].to_s.strip

      # Nothing set at all: the normal case on every node that does not use this.
      if digest_hex.empty? && scope_raw.empty? && name.empty?
        @errors = [].freeze
        @config = nil
        return
      end

      errors = []
      unless digest_hex.match?(SHA256_HEX)
        errors << "#{DIGEST_VAR} must be a 64-character lowercase hex SHA-256 digest"
      end

      fields = scope_raw.split(",").map(&:strip).reject(&:empty?)
      scope =
        if fields.any? && fields.all? { |f| f.match?(POSITIVE_INTEGER) }
          fields.map(&:to_i).select(&:positive?)
        else
          []
        end
      if scope.empty?
        errors << "#{SCOPE_VAR} must be a comma-separated list of positive project numbers"
      end

      unless name.match?(NAME_FORMAT)
        errors << "#{NAME_VAR} must be 1-64 characters of [A-Za-z0-9._-] " \
                  "(it appears in log lines and in the attributed login)"
      end

      @errors = errors.freeze
      @config =
        if errors.empty?
          Config.new(digest_hex.dup.freeze, scope.freeze, name.dup.freeze).freeze
        else
          nil
        end
    end
  end
end
