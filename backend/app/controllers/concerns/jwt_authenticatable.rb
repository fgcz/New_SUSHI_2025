module JwtAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_jwt_token
  end

  private

  def authenticate_jwt_token
    return if AuthenticationHelper.authentication_skipped?
    
    # Skip if user identification is not required for this API
    return if skip_jwt_authentication?
    
    token = extract_token_from_header
    return render_unauthorized unless token
    
    payload = decode_jwt_token(token)
    return render_unauthorized unless payload
    
    user = User.find_by(id: payload['user_id'])
    return render_unauthorized unless user
    
    @current_user = user
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    # Expect Bearer token format
    token = auth_header.split(' ').last
    token if token.present?
  end

  def decode_jwt_token(token)
    decoded = JWT.decode(token, JWT_SECRET_KEY, true, { algorithm: JWT_ALGORITHM })
    decoded[0]
  rescue JWT::DecodeError => e
    Rails.logger.error "JWT decode error: #{e.message}"
    nil
  end

  def render_unauthorized
    render json: { error: 'Unauthorized - JWT token required' }, status: :unauthorized
  end

  # List of APIs that don't require user identification
  def skip_jwt_authentication?
    # Authentication-related APIs (login, register, etc.)
    return true if controller_name == 'auth' && ['login', 'register'].include?(action_name)
    
    # Get authentication options
    return true if controller_name == 'authentication' && action_name == 'login_options'
    
    # Get authentication configuration
    return true if controller_name == 'authentication_config' && action_name == 'index'
    
    # Health check
    return true if request.path == '/up'
    
    # Root page
    return true if request.path == '/' && controller_name == 'home'
    
    false
  end
end 