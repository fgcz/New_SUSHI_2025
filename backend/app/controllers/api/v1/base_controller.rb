module Api
  module V1
    class BaseController < ApplicationController
      include ProjectAuthorizable
      # Accept a bearer ApiToken (SUSHI_API_TOKEN) as an alternative to JWT so
      # headless callers (sushi-chain) can drive basic ops. Prepends its own
      # before_action; when it sets @api_token the JWT layer stands down.
      include ApiTokenAuthenticatable

      # Base controller for API
      # JWT authentication required (except APIs excluded by skip_jwt_authentication?)
      # Skip CSRF protection for API endpoints
      skip_before_action :verify_authenticity_token

      before_action :ensure_jwt_authentication
      # Declared after the line above so it runs once a session has been established.
      before_action :authorize_bfabric_session_write!

      private

      # A session minted from a B-Fabric token may only WRITE if B-Fabric actually granted
      # `api:write`. Mirrors ApiTokenAuthenticatable#authorize_token_write! for the JWT
      # family, which until now had NO write-capability check of any kind: ApiToken#can_write?
      # guards the ApiToken bearer surface only, so the moment the Rack policy permits a
      # POST, every signed-in user could submit. The employee gate was the only narrowing.
      #
      # ADDITIVE, not a behaviour change: an LDAP-minted JWT carries no `src` claim and is
      # untouched. Only B-Fabric sessions are narrowed, and they are narrowed to no more
      # than the consent the user actually gave at B-Fabric — a session should never be
      # able to do more than the credential it was exchanged for.
      #
      # A headless write therefore clears four independent gates: B-Fabric consent scope,
      # the Rack SUSHI_WRITE_POLICY, LDAP project membership, and FGCZ.employee?.
      def authorize_bfabric_session_write!
        return if ApiTokenAuthenticatable::SAFE_HTTP_METHODS.include?(request.request_method)

        payload = @jwt_payload
        return unless payload.is_a?(Hash) && payload['src'] == 'bfabric'
        return if payload['scope'].to_s.split(/\s+/).include?('api:write')

        render json: {
          error: 'insufficient_scope',
          message: 'This session was established from a B-Fabric token that does not carry ' \
                   'the api:write scope. Request it at login and exchange a new session.'
        }, status: :forbidden
      end

      def ensure_jwt_authentication
        # A valid ApiToken already authenticated the request (headless path).
        return if @api_token

        # Do nothing if authentication is skipped
        return if AuthenticationHelper.authentication_skipped?

        # Skip if user identification is not required for this API
        return if skip_jwt_authentication?
        
        # Error if JWT authentication is not successful
        unless current_user.present?
          render json: { 
            error: 'JWT token required',
            message: 'Please include a valid JWT token in the Authorization header',
            example: 'Authorization: Bearer <your_jwt_token>'
          }, status: :unauthorized
        end
      end
      
      # List of APIs that don't require user identification (for BaseController)
      # Delegate to ApplicationController (Concern) for unified skip logic
      def skip_jwt_authentication?
        super
      end
    end
  end
end 