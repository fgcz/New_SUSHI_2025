export interface AuthenticationStatus {
  standard_login: boolean;
  oauth2_login: boolean;
  two_factor_auth: boolean;
  ldap_auth: boolean;
  wallet_auth: boolean;
  enabled_methods: string[];
  authentication_skipped: boolean;
  current_user?: string;
}

export interface AuthenticationConfig {
  standard_login: {
    enabled: boolean;
    allow_registration: boolean;
    allow_password_reset: boolean;
  };
  oauth2_login: {
    enabled: boolean;
    providers: {
      google: boolean;
      github: boolean;
    };
  };
  two_factor_auth: {
    enabled: boolean;
    require_setup: boolean;
    backup_codes: boolean;
  };
  ldap_auth: {
    enabled: boolean;
    allow_registration: boolean;
    allow_password_reset: boolean;
    auto_create_user: boolean;
  };
  wallet_auth: {
    enabled: boolean;
    network: string;
    require_signature: boolean;
  };
}

export interface LoginResponse {
  token: string;
  user: {
    id: number;
    login: string;
    email: string;
  };
  message: string;
}

export interface TokenVerifyResponse {
  user: any;
  valid: boolean;
}