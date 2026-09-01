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

// Mirrors the backend's TokenResponse contract (AuthController#token_response):
// { access_token, token_type, user: { user_id, login, projects } }. The previous
// shape here ({ token, user: { id, email }, message }) matched nothing the server
// sends, so a SUCCESSFUL login stored `undefined` as the bearer and reported failure.
export interface LoginResponse {
  access_token: string;
  token_type: string;
  user: {
    user_id: number;
    login: string;
    projects: number[];
  };
}

export interface TokenVerifyResponse {
  user: any;
  valid: boolean;
}