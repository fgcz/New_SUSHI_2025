module JwtAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_jwt_token
  end

  private

  def authenticate_jwt_token
    # A bearer ApiToken (prepended ApiTokenAuthenticatable) already authenticated
    # the request; do not also demand a JWT.
    return if defined?(@api_token) && @api_token

    return if AuthenticationHelper.authentication_skipped?

    # Skip if user identification is not required for this API
    return if skip_jwt_authentication?
    
    token = extract_token_from_header
    return render_unauthorized unless token
    
    payload = decode_jwt_token(token)
    return render_unauthorized unless payload

    user = User.find_by(id: payload['user_id'])
    return render_unauthorized unless user

    # Retained, not discarded. The payload carries the session's provenance (`src`) and,
    # for a B-Fabric session, the scopes B-Fabric actually granted — which is what
    # Api::V1::BaseController#authorize_bfabric_session_write! reads. Until now the JWT
    # path had NO write-capability check of any kind.
    @jwt_payload = payload
    @current_user = user
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header

    # Expect Bearer token format
    token = auth_header.split(' ').last
    token if token.present?
  end

  # decode_jwt_token is defined once in config/initializers/jwt.rb (single source,
  # with access-token type validation). No per-controller override here.

  def render_unauthorized
    render json: { error: 'Unauthorized - JWT token required' }, status: :unauthorized
  end

  # List of APIs that don't require user identification
  def skip_jwt_authentication?
    # Authentication-related APIs that don't use a bearer access token:
    #  - login/register: public (credentials in body)
    #  - login_options: public (advertises available auth methods)
    #  - refresh/logout: authenticated by the HttpOnly refresh_token cookie, not a bearer token
    # (me + logout-all keep bearer authentication.)
    return true if controller_name == 'auth' &&
                   %w[login register login_options refresh logout].include?(action_name)
    
    # Get authentication options
    return true if controller_name == 'authentication' && action_name == 'login_options'
    
    # Get authentication configuration
    return true if controller_name == 'authentication_config' && action_name == 'index'

    # B-Fabric OIDC session exchange: authenticated by a B-FABRIC bearer token, which is
    # not a SUSHI JWT and must not be run through this decoder. The controller verifies it
    # itself and mints the SUSHI JWT the rest of the system speaks.
    return true if controller_name == 'bfabric_auth'

    # Health check
    return true if request.path == '/up'
    
    # Root page
    return true if request.path == '/' && controller_name == 'home'
    
    # Test-only configurable exclusions
    if Rails.env.test?
      skip_paths = Array(AuthenticationHelper.config['skip_endpoints'])
      return true if skip_paths.include?(request.path)
    end
    
    false
  end
end 