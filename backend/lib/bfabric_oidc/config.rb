# frozen_string_literal: true

module BfabricOidc
  # An immutable snapshot of this node's OIDC posture, built once per process from ENV.
  #
  # FAILS CLOSED, AND FAILS QUIET AT BOOT. A misconfiguration disables the feature and is
  # reported once by config/initializers/bfabric_oidc.rb; it never raises during boot,
  # because this process is the one that submits every production job and must come up.
  class Config
    DEFAULT_REQUIRED_SCOPE = 'api:read'
    DEFAULT_HTTP_TIMEOUT   = 5
    DEFAULT_LEEWAY         = 30

    attr_reader :base_url, :access_token_audience, :expected_issuer, :jwks_uri,
                :client_id, :allowed_client_ids, :required_scope,
                :http_timeout, :leeway, :errors

    def self.build(env = ENV)
      new(env)
    end

    def initialize(env)
      @errors   = []
      @requested = env['BFABRIC_OIDC_ENABLED'].to_s.strip == '1'

      @base_url              = normalize_base(env['BFABRIC_OIDC_BASE_URL'])
      @access_token_audience = presence(env['BFABRIC_OIDC_AUDIENCE'])
      @expected_issuer       = presence(env['BFABRIC_OIDC_ISSUER'])
      @jwks_uri              = presence(env['BFABRIC_OIDC_JWKS_URI'])
      @client_id             = presence(env['BFABRIC_OIDC_CLIENT_ID'])
      @allowed_client_ids    = split_list(env['BFABRIC_OIDC_ALLOWED_CLIENT_IDS'])
      @required_scope        = presence(env['BFABRIC_OIDC_REQUIRED_SCOPE']) || DEFAULT_REQUIRED_SCOPE
      @http_timeout          = positive_int(env['BFABRIC_OIDC_HTTP_TIMEOUT']) || DEFAULT_HTTP_TIMEOUT
      @leeway                = positive_int(env['BFABRIC_OIDC_LEEWAY']) || DEFAULT_LEEWAY

      validate!

      @allowed_client_ids.freeze
      @errors.freeze
      freeze
    end

    # Requested AND usable. A node that asked for the feature but misconfigured it gets
    # the feature OFF, not a half-configured verifier.
    def enabled?
      @requested && @errors.empty?
    end

    def requested?
      @requested
    end

    # The client allow-list is OPT-IN, and when opted into it is enforced STRICTLY —
    # a token whose claim set carries neither `client_id` nor `azp` is REJECTED rather
    # than waved through.
    #
    # This is deliberately stricter than "log a known gap and continue". Production's
    # `claims_supported` lists neither claim (measured 2026-09-03), so the claim is
    # likely absent in practice; a check that silently passes everything is worse than
    # no check, because it reads like a control in a review. Leaving the variable unset
    # states plainly that there is NO per-client narrowing; setting it states "I measured
    # the claim, enforce it". Either way the reader is not misled.
    def enforce_client_allow_list?
      @allowed_client_ids.any?
    end

    def discovery_url
      return nil if @base_url.nil?

      "#{@base_url}/.well-known/openid-configuration"
    end

    private

    def validate!
      return unless @requested

      @errors << 'BFABRIC_OIDC_BASE_URL is not set (e.g. https://fgcz-bfabric.uzh.ch/bfabric)' if @base_url.nil?

      if @access_token_audience.nil?
        # The hard gate. Without an expected `aud` a token minted for any other B-Fabric
        # relying party verifies here on signature alone, which is the confused-deputy
        # case this endpoint exists to avoid. The value is a MEASUREMENT (step M1), not a
        # guess, so the feature stays off until someone has measured it.
        @errors << 'BFABRIC_OIDC_AUDIENCE is not set, so a token\'s `aud` cannot be ' \
                   'checked. Measure it from a real device-code login ' \
                   '(scripts/bfabric_oauth_check/measure_token_claims.sh) before enabling.'
      end

      return if @base_url.nil?

      uri = begin
        URI.parse(@base_url)
      rescue URI::InvalidURIError
        nil
      end
      @errors << 'BFABRIC_OIDC_BASE_URL is not an http(s) URL' unless uri.is_a?(URI::HTTP)
    end

    def normalize_base(value)
      v = presence(value)
      return nil if v.nil?

      v.sub(%r{/+\z}, '')
    end

    def presence(value)
      v = value.to_s.strip
      v.empty? ? nil : v
    end

    def split_list(value)
      presence(value).to_s.split(',').map(&:strip).reject(&:empty?)
    end

    def positive_int(value)
      v = presence(value)
      return nil if v.nil?

      i = v.to_i
      i.positive? ? i : nil
    end
  end
end
