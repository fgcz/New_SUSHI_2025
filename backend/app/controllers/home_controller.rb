class HomeController < ApplicationController
  # Skip authentication check for home page when auth is disabled
  if respond_to?(:authenticate_user!)
    skip_before_action :authenticate_user!, if: :skip_authentication?
  end
  
  def index
    # Return JSON response for API consumption
    render json: {
      message: 'Welcome to Sushi App',
      current_user: current_user&.login,
      authentication_status: AuthenticationHelper.authentication_skipped? ? 'skipped' : 'required',
      available_endpoints: [
        '/api/v1/hello',
        '/auth/login_options',
        '/api/v1/authentication_config'
      ]
    }
  end
  
  private
  
  def skip_authentication?
    AuthenticationHelper.authentication_skipped?
  end
end 