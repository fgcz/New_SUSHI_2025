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

  # B-Fabric OIDC login. Configured from ENV via BfabricOidc, NOT from the `oauth2_login`
  # key in authentication.yml — deliberately. Flipping `oauth2_login.enabled` adds
  # `devise :omniauthable`, re-wires the devise routes (see config/routes.rb) and sends
  # callbacks to User.from_omniauth, which SELECTs provider/uid columns the production
  # users table does not have. That scaffolding stays dead; this is a separate switch.
  def self.bfabric_oidc_enabled?
    defined?(BfabricOidc) ? BfabricOidc.enabled? : false
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

  def self.legacy_database?
    config['legacy_database'] == true
  end

  def self.enabled_auth_methods
    methods = []
    methods << :standard if standard_login_enabled?
    methods << :oauth2 if oauth2_login_enabled?
    methods << :two_factor if two_factor_auth_enabled?
    methods << :ldap if ldap_auth_enabled?
    methods << :wallet if wallet_auth_enabled?
    # Consequence worth knowing: this makes authentication_skipped? false on a node that
    # had no other login method enabled. 082 and 083 both set SUSHI_REQUIRE_AUTH=1, so it
    # is inert there, but a developer instance that turns B-Fabric OIDC on will start
    # demanding a credential — which is the correct behaviour, just not a silent one.
    methods << :bfabric_oidc if bfabric_oidc_enabled?
    methods
  end
  
  # Single choke point for "is authentication skipped for this request?".
  #
  # Fail-CLOSED in production: authentication is NEVER skipped there unless an
  # operator explicitly opts into anonymous access (SUSHI_ALLOW_ANONYMOUS=1).
  # This closes the "anonymous 200 + all-projects fallback on the live prod DB"
  # hole: a production surface requires a credential (bearer ApiToken or JWT)
  # regardless of which interactive login methods are enabled — so we do NOT need
  # to stand up LDAP/standard_login just to force 401. SUSHI_REQUIRE_AUTH=1 forces
  # the same in any environment.
  def self.authentication_skipped?
    return false if ENV["SUSHI_REQUIRE_AUTH"] == "1"
    return false if Rails.env.production? && ENV["SUSHI_ALLOW_ANONYMOUS"] != "1"

    enabled_auth_methods.empty?
  end
  
  def self.get_default_user
    # Return non-persistent anonymous user when not found
    if legacy_database?
      # In legacy mode, email column doesn't exist
      User.find_by(login: 'anonymous') || User.new(login: 'anonymous')
    else
      User.find_by(login: 'anonymous') || User.new(login: 'anonymous', email: 'anonymous@example.com')
    end
  end
end 