module Api
  module V1
    class BaseController < ApplicationController
      # Base controller for API
      # JWT authentication required (except APIs excluded by skip_jwt_authentication?)
      # Skip CSRF protection for API endpoints
      skip_before_action :verify_authenticity_token
      
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
      # Delegate to ApplicationController (Concern) for unified skip logic
      def skip_jwt_authentication?
        super
      end
    end
  end
end 