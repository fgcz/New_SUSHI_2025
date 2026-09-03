# frozen_string_literal: true

module Api
  module V1
    # B-Fabric OIDC — "the ticket at the door".
    #
    # A caller presents a B-FABRIC access token ONCE, here, and receives the SUSHI JWT the
    # rest of the system already speaks. The B-Fabric token is torn at the door: it is
    # never stored, never forwarded, and never accepted on any other route.
    #
    # Two ways in, one session model:
    #
    #   #session       an agent that already holds a B-Fabric token (it ran the device flow
    #                  itself) exchanges it here. No browser anywhere.
    #   #device_start  a BROWSER asks this backend to begin a device login;
    #   #device_poll   ...and collects the finished SUSHI session from it. The browser
    #                  never sees a B-Fabric token — see BfabricOidc::DeviceFlow for why
    #                  that matters more than it looks.
    #
    # WHY ONE ROUTE FOR THE RAW BEARER. Accepting a raw B-Fabric bearer across /api/v1
    # would be a textbook confused deputy: B-Fabric's public `CLI` client needs no
    # registration, so a token any tool obtained for its own purposes would become a full
    # New SUSHI session, job submission included. Production advertises neither `client_id`
    # nor `azp` in `claims_supported` — though the token does in fact carry `client_id`
    # (measured 2026-09-03) — so the narrowing is real but partial, and the exposure is
    # confined to one exchange rather than left to a claim that may not exist.
    #
    # WHY EVERY ROUTE HERE IS A GET. Middleware::SushiReadOnlyGuard returns early for safe
    # methods before consulting any policy, so none of this needs an entry in
    # NO_WRITE_PATHS. That list is a CLAIM ABOUT THE HANDLER against a database shared with
    # live legacy production; not growing it is a deliberate property, asserted by section 7
    # of the 082 gate check. #session performs ONE SELECT and no write of any kind.
    class BfabricAuthController < ApplicationController
      include SessionIssuing

      skip_before_action :verify_authenticity_token

      # `reason` is stable and machine-readable so a failing caller can tell "my token
      # expired" from "this node does not trust my issuer" without reading our logs.
      rescue_from BfabricOidc::TokenVerifier::Rejected do |e|
        render_error(:unauthorized, 'invalid_bfabric_token', e.message, reason: e.reason)
      end

      # B-Fabric is down or unreachable. That is OUR problem, not a bad credential, and
      # answering 401 would send people to re-authenticate pointlessly.
      rescue_from BfabricOidc::Unreachable do |e|
        Rails.logger.error("BfabricAuthController: B-Fabric unreachable: #{e.message}")
        render_error(:service_unavailable, 'bfabric_unreachable',
                     'Could not reach B-Fabric to complete the login. Try again shortly.')
      end

      # GET /api/v1/auth/bfabric/session
      # For a caller that already holds a B-Fabric access token.
      def session
        return render_disabled unless BfabricOidc.enabled?

        raw = bearer_credential
        return render_error(:unauthorized, 'missing_bearer',
                            'Present a B-Fabric access token as `Authorization: Bearer <token>`.') if raw.blank?

        render_session_for(raw)
      end

      # GET /api/v1/auth/bfabric/device/start[?write=1]
      # Begins a browser login. Returns the code and URL to show the human — and NOT the
      # `device_code`, which would let whoever saw the response redeem the login instead.
      def device_start
        return render_disabled unless BfabricOidc.config.device_login_enabled?

        payload = BfabricOidc::DeviceFlow.start(scope: requested_scope)
        no_store!
        Rails.logger.info('BfabricAuthController: device login started ' \
                          "(#{BfabricOidc::DeviceFlow.pending_count} in progress)")
        render json: payload
      rescue BfabricOidc::DeviceFlow::TooBusy
        render_error(:service_unavailable, 'too_many_logins_in_progress',
                     'Too many sign-ins are already in progress on this node. Try again in a minute.')
      end

      # GET /api/v1/auth/bfabric/device/poll?handle=...
      # One poll. The browser repeats this on the interval it was given.
      def device_poll
        return render_disabled unless BfabricOidc.config.device_login_enabled?

        handle = params[:handle].to_s
        return render_error(:bad_request, 'missing_handle', 'No login handle was supplied.') if handle.empty?

        status, payload = BfabricOidc::DeviceFlow.poll(handle)

        case status
        when :pending
          render json: { status: 'pending' }
        when :too_soon
          # The interval is enforced HERE, not trusted from the client: this route is
          # unauthenticated, and a client that ignored it would use us to hammer B-Fabric.
          render json: { status: 'pending', retry_in: payload }
        when :expired
          render_error(:unauthorized, 'device_code_expired',
                       'This sign-in was not approved in time. Start again.')
        when :error
          render_error(:unauthorized, 'device_login_failed', payload.to_s)
        when :ok
          # `payload` is the B-Fabric access token. It is verified, spent and dropped
          # inside this request; it is never written to the response.
          no_store!
          render_session_for(payload)
        end
      end

      private

      # The single place a B-Fabric token becomes a SUSHI session, shared by both entries.
      def render_session_for(raw_bfabric_token)
        result = BfabricOidc::TokenVerifier.verify(raw_bfabric_token)
        user = User.find_by(login: result.sub)

        # Deliberately NOT a create. `auto_create_user` is false and INSERT is forbidden on
        # the production node, so a person B-Fabric knows but SUSHI does not is refused —
        # the same answer the LDAP login gives, for the same reason.
        unless user
          Rails.logger.warn(
            "BfabricAuthController: B-Fabric token verified for sub=#{result.sub} " \
            'but no local users row exists; refusing (no row is created here)'
          )
          return render_error(:unauthorized, 'unknown_user',
                              'Authentication succeeded at B-Fabric, but this login has no ' \
                              'SUSHI user record. Ask a SUSHI administrator to add it.')
        end

        no_store!
        Rails.logger.info(
          "BfabricAuthController: issued a SUSHI session for login=#{user.login} " \
          "via B-Fabric OIDC (scopes=#{result.scope_string.inspect})"
        )

        render json: establish_session(user, src: 'bfabric', scope: result.scope_string)
                       .merge(status: 'ok', expires_in: JWT_ACCESS_TTL.to_i,
                              granted_scopes: result.scopes)
      end

      # The browser asks for write capability explicitly, because a session that can submit
      # jobs should be a choice rather than a default. Without api:write the backend refuses
      # every non-safe method with 403 insufficient_scope.
      def requested_scope
        scope = BfabricOidc.config.device_scope
        return scope unless params[:write].to_s == '1'
        return scope if scope.split.include?('api:write')

        "#{scope} api:write"
      end

      # RFC 6749 §5.1 — a response carrying a token must not be cached anywhere.
      def no_store!
        response.set_header('Cache-Control', 'no-store')
        response.set_header('Pragma', 'no-cache')
      end

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
