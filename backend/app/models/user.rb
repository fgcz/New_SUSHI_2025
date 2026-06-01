class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  
  # Dynamic devise configuration based on authentication settings
  devise_modules = []
  
  # Check if legacy database mode (old SUSHI MySQL DB without email/password columns)
  legacy_mode = AuthenticationHelper.legacy_database?
  
  # Check if any authentication method is enabled
  if AuthenticationHelper.enabled_auth_methods.any?
    # Always include basic modules
    devise_modules << :registerable if AuthenticationHelper.standard_login_enabled?
    devise_modules << :rememberable
    devise_modules << :trackable
    # Only include :validatable if not in legacy database mode (requires email/password columns)
    devise_modules << :validatable unless legacy_mode
    
    # Add authentication strategies based on configuration
    if AuthenticationHelper.standard_login_enabled?
      devise_modules << :database_authenticatable
      devise_modules << :recoverable if AuthenticationHelper.config['standard_login']['allow_password_reset']
    end
    
    # For LDAP authentication, we need database_authenticatable as fallback
    if AuthenticationHelper.ldap_auth_enabled?
      devise_modules << :database_authenticatable unless devise_modules.include?(:database_authenticatable)
      if defined?(Devise::Models::LdapAuthenticatable)
        devise_modules << :ldap_authenticatable
      end
    end
    
    if AuthenticationHelper.oauth2_login_enabled?
      devise_modules << :omniauthable
    end
    
    if AuthenticationHelper.two_factor_auth_enabled?
      devise_modules << :two_factor_authenticatable
    end
    
    # Apply devise configuration
    devise *devise_modules
  else
    # No authentication enabled - skip all authentication
    # In legacy mode, skip :validatable as well
    if legacy_mode
      devise :trackable
    else
      devise :trackable, :validatable
    end
  end

  # Setup accessible (or protected) attributes for your model
#  attr_accessible :login, :password, :password_confirmation, :remember_me, :selected_project
  # attr_accessible :title, :body
  has_many :data_sets
  
  # Skip additional associations and features in legacy database mode
  unless AuthenticationHelper.legacy_database?
    # OAuth2 associations
    has_many :oauth_applications, class_name: 'Doorkeeper::Application', as: :owner
    
    # Two-factor authentication fields
    if AuthenticationHelper.two_factor_auth_enabled?
      has_one_time_password
    end
    
    # Wallet authentication fields
    if AuthenticationHelper.wallet_auth_enabled?
      has_one :wallet_connection, dependent: :destroy
    end
  end
  
  # LDAP attribute mapping for bfabric LDAP
  def ldap_before_save
    return unless AuthenticationHelper.ldap_auth_enabled?
    return if AuthenticationHelper.legacy_database?
    return unless defined?(Devise::LDAP::Adapter)
    
    # Map LDAP attributes to user model
    if Devise::LDAP::Adapter.get_ldap_param(self.login, "mail")
      self.email = Devise::LDAP::Adapter.get_ldap_param(self.login, "mail").first
    end
    
    # Set default email if not available from LDAP
    if self.email.blank?
      self.email = "#{self.login}@bfabric.org"
    end
  end
  
  # OAuth2 methods (not available in legacy database mode)
  def self.from_omniauth(auth)
    return nil if AuthenticationHelper.legacy_database?
    
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.login = auth.info.name || auth.info.email.split('@').first
      user.password = Devise.friendly_token[0, 20]
    end
  end
  
  # Wallet authentication methods (not available in legacy database mode)
  def connect_wallet(address, signature = nil)
    return unless AuthenticationHelper.wallet_auth_enabled?
    return if AuthenticationHelper.legacy_database?
    
    wallet_connection || build_wallet_connection
    wallet_connection.update(
      address: address,
      network: AuthenticationHelper.wallet_config['network'],
      last_used_at: Time.current
    )
  end
  
  def wallet_connected?
    return false if AuthenticationHelper.legacy_database?
    wallet_connection&.address.present?
  end
end
