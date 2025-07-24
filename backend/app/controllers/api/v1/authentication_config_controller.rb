module Api
  module V1
    class AuthenticationConfigController < BaseController
      before_action :require_admin, except: [:index]
      
      # Get current authentication configuration
      def index
        render json: {
          standard_login: {
            enabled: AuthenticationHelper.standard_login_enabled?,
            allow_registration: AuthenticationHelper.config['standard_login']['allow_registration'],
            allow_password_reset: AuthenticationHelper.config['standard_login']['allow_password_reset']
          },
          oauth2_login: {
            enabled: AuthenticationHelper.oauth2_login_enabled?,
            providers: {
              google: AuthenticationHelper.oauth2_provider_enabled?('google'),
              github: AuthenticationHelper.oauth2_provider_enabled?('github')
            }
          },
          two_factor_auth: {
            enabled: AuthenticationHelper.two_factor_auth_enabled?,
            require_setup: AuthenticationHelper.config['two_factor_auth']['require_setup'],
            backup_codes: AuthenticationHelper.config['two_factor_auth']['backup_codes']
          },
          ldap_auth: {
            enabled: AuthenticationHelper.ldap_auth_enabled?,
            allow_registration: AuthenticationHelper.ldap_config['allow_registration'],
            allow_password_reset: AuthenticationHelper.ldap_config['allow_password_reset'],
            auto_create_user: AuthenticationHelper.ldap_config['auto_create_user']
          },
          wallet_auth: {
            enabled: AuthenticationHelper.wallet_auth_enabled?,
            network: AuthenticationHelper.wallet_config['network'],
            require_signature: AuthenticationHelper.wallet_config['require_signature']
          }
        }
      end
      
      # Update authentication configuration
      def update
        # In actual implementation, implement dynamic configuration file update logic
        # This is a simplified implementation
        render json: { message: 'Configuration updated successfully' }
      end
      
      private
      
      def require_admin
        # Admin permission check implementation
        unless current_user.admin?
          render json: { error: 'Admin access required' }, status: :forbidden
        end
      end
    end
  end
end 