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
        user_data = {
          id: current_user.id,
          login: current_user.login,
          created_at: current_user.created_at
        }
        # Include email only if column exists (not in legacy database mode)
        user_data[:email] = current_user.email if current_user.respond_to?(:email) && !AuthenticationHelper.legacy_database?
        
        render json: {
          user: user_data,
          authentication_method: 'JWT',
          token_valid: true
        }
      end
    end
  end
end 