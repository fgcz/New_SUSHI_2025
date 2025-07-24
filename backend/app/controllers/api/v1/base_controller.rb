module Api
  module V1
    class BaseController < ApplicationController
          # Base controller for API
    # JWT authentication required (except APIs excluded by skip_jwt_authentication?)
      
      before_action :ensure_jwt_authentication
      
      private
      
      def ensure_jwt_authentication
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
      def skip_jwt_authentication?
        # Authentication-related APIs (login, register, etc.)
        return true if controller_name == 'auth' && ['login', 'register'].include?(action_name)
        
        # Get authentication options
        return true if controller_name == 'authentication' && action_name == 'login_options'
        
        # Get authentication configuration
        return true if controller_name == 'authentication_config' && action_name == 'index'
        
        # Health check
        return true if request.path == '/up'
        
        false
      end
    end
  end
end 