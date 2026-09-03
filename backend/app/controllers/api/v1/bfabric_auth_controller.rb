# frozen_string_literal: true

module Api
  module V1
    # B-Fabric OIDC session exchange — "the ticket at the door".
    #
    # A caller presents a B-FABRIC access token ONCE, here, and receives the SUSHI JWT the
    # rest of the system already speaks. The B-Fabric token is torn at the door: it is
    # never stored, never forwarded, and never accepted on any other route.
    #
    # WHY ONE ROUTE AND NOT EVERY ROUTE. Accepting a raw B-Fabric bearer on the whole
    # /api/v1 surface would be a textbook confused deputy: B-Fabric's public `CLI` client
    # needs no registration, so a token any tool obtained for its own purposes would become
    # a full New SUSHI session, job submission included. Production's `claims_supported`
    # lists neither `client_id` nor `azp` (measured 2026-09-03), so we cannot reliably tell
    # which client a token was minted for — which is exactly why the exposure is confined
    # to one exchange instead of being narrowed by a claim that may not exist.
    #
    # WHY IT IS A GET. Middleware::SushiReadOnlyGuard returns early for safe methods before
    # consulting any policy, so this route needs no entry in NO_WRITE_PATHS. That list is a
    # CLAIM ABOUT THE HANDLER against a database shared with live legacy production; not
    # growing it is a deliberate property of this design, asserted by the 082 gate check.
    # The action performs ONE SELECT (`User.find_by(login:)`) and no write of any kind.
    #
    # THE HEADLESS PATH DOES NOT PASS THROUGH HERE TO REACH B-FABRIC. An agent runs the
    # device-code flow against B-Fabric itself (public client `CLI`, no registration, no
    # secret, no redirect_uri) and only then calls this endpoint. We never see, hold or
    # refresh its B-Fabric refresh token.
    class BfabricAuthController < ApplicationController
      include SessionIssuing

      skip_before_action :verify_authenticity_token

      # GET /api/v1/auth/bfabric/session
      def session
        return render_disabled unless BfabricOidc.enabled?

        raw = bearer_credential
        return render_error(:unauthorized, 'missing_bearer',
                            'Present a B-Fabric access token as `Authorization: Bearer <token>`.') if raw.blank?

        result = BfabricOidc::TokenVerifier.verify(raw)
        user = User.find_by(login: result.sub)

        # Deliberately NOT a create. `auto_create_user` is false and INSERT is forbidden on
        # the production node, so a person B-Fabric knows but SUSHI does not is refused —
        # the same answer the LDAP login gives, for the same reason. The message says so
        # rather than reading as a credential failure.
        unless user
          Rails.logger.warn(
            "BfabricAuthController: B-Fabric token verified for sub=#{result.sub} " \
            'but no local users row exists; refusing (no row is created here)'
          )
          return render_error(:unauthorized, 'unknown_user',
                              'Authentication succeeded at B-Fabric, but this login has no ' \
                              'SUSHI user record. Ask a SUSHI administrator to add it.')
        end

        # RFC 6749 §5.1 — a response carrying a token must not be cached anywhere.
        response.set_header('Cache-Control', 'no-store')
        response.set_header('Pragma', 'no-cache')

        Rails.logger.info(
          "BfabricAuthController: issued a SUSHI session for login=#{user.login} " \
          "via B-Fabric OIDC (scopes=#{result.scope_string.inspect})"
        )

        render json: establish_session(user, src: 'bfabric', scope: result.scope_string)
                       .merge(expires_in: JWT_ACCESS_TTL.to_i, granted_scopes: result.scopes)
      rescue BfabricOidc::TokenVerifier::Rejected => e
        # `reason` is stable and machine-readable so a failing agent can tell "my token
        # expired" from "this node does not trust my issuer" without reading our logs.
        render_error(:unauthorized, 'invalid_bfabric_token', e.message, reason: e.reason)
      rescue BfabricOidc::Unreachable => e
        # B-Fabric is down or unreachable. That is OUR problem, not a bad credential, and
        # answering 401 here would send people to re-authenticate pointlessly.
        Rails.logger.error("BfabricAuthController: B-Fabric unreachable: #{e.message}")
        render_error(:service_unavailable, 'bfabric_unreachable',
                     'Could not reach B-Fabric to verify the token. Try again shortly.')
      end

      private

      # Anchored on the scheme, unlike JwtAuthenticatable#extract_token_from_header which
      # takes the last whitespace-separated word and so accepts `Authorization: Basic <jwt>`.
      # A new credential family should not inherit that laxity.
      def bearer_credential
        request.headers['Authorization'].to_s[/\ABearer\s+(.+)\z/i, 1]
      end

      # 404, not 403: on a node where the feature is off the route should look like it does
      # not exist, and the 082 gate check asserts exactly that.
      def render_disabled
        render json: {
          error: 'bfabric_oidc_disabled',
          message: 'B-Fabric OIDC login is not enabled on this node.'
        }, status: :not_found
      end

      def render_error(status, error, message, extra = {})
        render json: { error: error, message: message }.merge(extra), status: status
      end
    end
  end
end
