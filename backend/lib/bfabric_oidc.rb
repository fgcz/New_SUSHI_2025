# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# B-Fabric OpenID Connect support.
#
# WHY THIS IS `require_relative`'d FROM config/application.rb INSTEAD OF AUTOLOADED
# FROM lib/ — the same reason lib/env_api_token.rb is: the development reloader discards
# autoloaded constants between requests, and THE PRODUCTION NODE (082) RUNS IN DEVELOPMENT
# MODE. Autoloading would therefore
#   (a) re-read ENV on every request, undoing the once-per-process freeze of the node's
#       OIDC posture — the same class of hazard EnvApiToken guards against; and
#   (b) throw the JWKS cache away every request, turning one network fetch per hour into
#       one per request, against an external service, ON THE LOGIN PATH.
#
# Scope of this module: it VERIFIES tokens B-Fabric issued. It never obtains one for the
# headless caller — an agent runs the device-code flow against B-Fabric itself and only
# then talks to us. See app/controllers/api/v1/bfabric_auth_controller.rb.
module BfabricOidc
  class Error < StandardError; end

  # The B-Fabric side could not be reached or answered unusably. Surfaces as 503, never
  # as "your token is bad": a network fault is not an authentication failure and telling
  # the two apart is what makes the endpoint debuggable.
  class Unreachable < Error; end

  class << self
    # Frozen once per process. `BfabricOidc.reset!` exists for specs only.
    def config
      @config ||= Config.build
    end

    def enabled?
      config.enabled?
    end

    # Reasons the feature is OFF despite BFABRIC_OIDC_ENABLED=1. Reported at boot.
    def errors
      config.errors
    end

    def logger
      defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
    end

    # Test seam. Never called by application code.
    def reset!
      @config = nil
      JwksCache.reset!
    end
  end
end

require_relative 'bfabric_oidc/config'
require_relative 'bfabric_oidc/jwks_cache'
require_relative 'bfabric_oidc/token_verifier'
