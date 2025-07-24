module Api
  module V1
    class TestController < BaseController
      # Test API that requires JWT authentication
      
      def protected
        render json: {
          message: 'This is a protected endpoint',
          current_user: current_user.login,
          user_id: current_user.id,
          timestamp: Time.current,
          jwt_authenticated: true
        }
      end
      
      def user_info
        render json: {
          user: {
            id: current_user.id,
            login: current_user.login,
            email: current_user.email,
            created_at: current_user.created_at
          },
          authentication_method: 'JWT',
          token_valid: true
        }
      end
    end
  end
end 