# frozen_string_literal: true

require 'jwt'

module BfabricOidc
  # Verifies a B-Fabric-issued access token presented as a bearer credential.
  #
  # Verification happens LOCALLY against B-Fabric's published JWKS. No introspection call
  # is made: `introspection_endpoint` exists but requires client_secret_basic, i.e. a
  # confidential client, which the headless path deliberately does not have.
  #
  # The consequence, stated rather than hidden: a token revoked at B-Fabric keeps
  # verifying here until it expires (3600 s). See the risk list in the design.
  class TokenVerifier
    ALGORITHMS = %w[RS256].freeze

    # `sub` is the B-Fabric login string and it flows into `User.find_by(login:)` and into
    # FGCZ.get_user_projects2, so its shape is constrained here as well. This is defence in
    # depth, NOT the fix for the shell interpolation in lib/fgcz.rb (deferred, recorded in
    # L2 deferred_prexisting_defects_found_during_oauth2_design_20260903).
    SUB_FORMAT = /\A[A-Za-z0-9._-]{1,64}\z/

    Result = Struct.new(:sub, :scopes, :claims, keyword_init: true) do
      def scope_string
        Array(scopes).join(' ')
      end
    end

    # A token we will not accept. `reason` is a stable machine-readable string echoed to
    # the caller so a failing agent can tell "my token expired" from "this node does not
    # trust my issuer" — the operability judge's ask, and the difference between a
    # five-minute fix and an afternoon.
    class Rejected < StandardError
      attr_reader :reason

      def initialize(reason, message = nil)
        @reason = reason
        super(message || reason.to_s)
      end
    end

    def self.verify(raw, audience: nil)
      new(raw, audience: audience).verify
    end

    def initialize(raw, audience: nil)
      @raw = raw.to_s
      @config = BfabricOidc.config
      @audience = audience || @config.access_token_audience
    end

    # Returns a Result, raises Rejected (the token is bad) or Unreachable (we are).
    def verify
      raise Rejected.new('malformed', 'not a three-segment JWS') unless @raw.count('.') == 2
      raise Rejected.new('not_configured', 'no expected audience configured') if @audience.to_s.empty?

      claims = decode

      check_not_an_id_token!(claims)
      check_client!(claims)
      scopes = check_scope!(claims)
      sub = check_sub!(claims)

      Result.new(sub: sub, scopes: scopes, claims: claims)
    end

    private

    def decode
      payload, _header = JWT.decode(
        @raw, nil, true,
        algorithms: ALGORITHMS,
        jwks: JwksCache.jwks_loader,
        iss: JwksCache.expected_issuer,
        verify_iss: true,
        aud: @audience,
        verify_aud: true,
        verify_expiration: true,
        verify_not_before: true,
        leeway: @config.leeway
      )
      payload
    rescue JWT::ExpiredSignature
      raise Rejected.new('expired', 'the B-Fabric token has expired')
    rescue JWT::ImmatureSignature
      raise Rejected.new('not_yet_valid', 'the B-Fabric token is not valid yet (nbf)')
    rescue JWT::InvalidIssuerError
      raise Rejected.new('bad_issuer', 'the token was not issued by the configured B-Fabric instance')
    rescue JWT::InvalidAudError
      raise Rejected.new('bad_audience', 'the token was not minted for this audience')
    rescue JWT::IncorrectAlgorithm
      # Covers the algorithm-confusion attempt: an HS256 token forged with the published
      # RSA modulus as the HMAC key never reaches signature verification, because RS256 is
      # the only algorithm this verifier will consider.
      raise Rejected.new('bad_algorithm', 'only RS256 is accepted')
    rescue JWT::VerificationError
      raise Rejected.new('bad_signature', 'signature verification failed')
    rescue Unreachable
      raise
    rescue JWT::DecodeError => e
      # Includes "No key id (kid) found from token headers" and any malformed input the
      # segment count did not catch. Never echo the token or the raw message to the caller.
      log(:info, "token rejected during decode: #{e.class}: #{e.message}")
      raise Rejected.new('undecodable', 'the token could not be decoded')
    end

    # An id_token presented where an access token belongs. `aud` alone would normally
    # catch this (an id_token's audience is the CLIENT, an access token's is the API), so
    # this is defence in depth for the case where the two happen to coincide.
    def check_not_an_id_token!(claims)
      return unless claims.key?('at_hash')

      raise Rejected.new('at_hash_present', 'this looks like an id_token, not an access token')
    end

    def check_client!(claims)
      return unless @config.enforce_client_allow_list?

      presented = claims['client_id'] || claims['azp']
      if presented.to_s.empty?
        raise Rejected.new('client_claim_absent',
                           'BFABRIC_OIDC_ALLOWED_CLIENT_IDS is set but the token carries ' \
                           'neither client_id nor azp')
      end
      return if @config.allowed_client_ids.include?(presented.to_s)

      raise Rejected.new('client_not_allowed', 'the token was minted for a client this node does not accept')
    end

    def check_scope!(claims)
      scopes = extract_scopes(claims)
      required = @config.required_scope
      return scopes if required.to_s.empty? || scopes.include?(required)

      raise Rejected.new('missing_scope', "the token does not carry the required scope #{required}")
    end

    def check_sub!(claims)
      sub = claims['sub'].to_s
      return sub if SUB_FORMAT.match?(sub)

      raise Rejected.new('malformed_sub', 'the token subject is not a usable login string')
    end

    # B-Fabric sends `scope` as a space-delimited string; `scp` as an array is the other
    # common spelling. Accept both rather than assume.
    def extract_scopes(claims)
      raw = claims['scope'] || claims['scp']
      case raw
      when Array  then raw.map(&:to_s)
      when String then raw.split(/\s+/).reject(&:empty?)
      else []
      end
    end

    def log(level, message)
      BfabricOidc.logger&.public_send(level, "BfabricOidc::TokenVerifier: #{message}")
    end
  end
end
