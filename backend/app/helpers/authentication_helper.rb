module AuthenticationHelper
  def self.config
    @config ||= begin
      config_path = Rails.root.join('config', 'authentication.yml')
      yaml_content = File.read(config_path)
      erb_content = ERB.new(yaml_content).result
      YAML.load(erb_content, aliases: true)[Rails.env]
    rescue => e
      Rails.logger.error "Error loading authentication config: #{e.message}"
      # Fallback configuration
      {
        'standard_login' => { 'enabled' => false },
        'oauth2_login' => { 'enabled' => false, 'providers' => {} },
        'two_factor_auth' => { 'enabled' => false },
        'ldap_auth' => { 'enabled' => false },
        'wallet_auth' => { 'enabled' => false }
      }
    end
  end

  def self.standard_login_enabled?
    config['standard_login']['enabled']
  end

  def self.oauth2_login_enabled?
    config['oauth2_login']['enabled']
  end

  def self.two_factor_auth_enabled?
    config['two_factor_auth']['enabled']
  end

  def self.ldap_auth_enabled?
    config['ldap_auth']['enabled']
  end

  def self.wallet_auth_enabled?
    config['wallet_auth']['enabled']
  end

  def self.oauth2_provider_enabled?(provider)
    config['oauth2_login']['providers'][provider]['enabled']
  end

  def self.oauth2_provider_config(provider)
    config['oauth2_login']['providers'][provider]
  end

  def self.ldap_config
    config['ldap_auth']
  end

  def self.wallet_config
    config['wallet_auth']
  end

  def self.enabled_auth_methods
    methods = []
    methods << :standard if standard_login_enabled?
    methods << :oauth2 if oauth2_login_enabled?
    methods << :two_factor if two_factor_auth_enabled?
    methods << :ldap if ldap_auth_enabled?
    methods << :wallet if wallet_auth_enabled?
    methods
  end
  
  def self.authentication_skipped?
    enabled_auth_methods.empty?
  end
  
  def self.get_default_user
    # Return non-persistent anonymous user when not found
    User.find_by(login: 'anonymous') || User.new(login: 'anonymous', email: 'anonymous@example.com')
  end
end 