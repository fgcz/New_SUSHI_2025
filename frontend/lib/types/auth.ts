export interface AuthenticationStatus {
  ldap_auth: boolean;
  authentication_skipped: boolean;
}

export interface AuthState extends AuthenticationStatus {
  current_user: string | null;
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
  access_token: string;
  token_type: string;
  user: {
    id: number;
    login: string;
    email: string;
  };
}

export interface TokenVerifyResponse {
  user_id: number;
  login: string;
  projects: number[];
}
