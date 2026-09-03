export interface AuthenticationStatus {
  standard_login: boolean;
  oauth2_login: boolean;
  two_factor_auth: boolean;
  ldap_auth: boolean;
  wallet_auth: boolean;
  // B-Fabric OIDC. Answered by BOTH login_options endpoints; the backend keeps them in
  // step because advertising it on only one makes the button silently never appear.
  bfabric_oidc?: boolean;
  enabled_methods: string[];
  authentication_skipped: boolean;
  current_user?: string;
}

// What the backend hands back when it has begun a device login on our behalf.
//
// Note what is ABSENT: `device_code`. Whoever holds that can redeem the login at B-Fabric
// themselves, so it stays on the server and the browser carries only the opaque `handle`.
export interface BfabricDeviceStart {
  handle: string;
  user_code: string;
  verification_uri: string;
  // RFC 8628's no-typing-required URL. B-Fabric does not send it (measured on both
  // instances), so `verification_uri_guess` is our constructed attempt at the same thing:
  // the same page with `?user_code=...` appended. If the page ignores it the user types
  // the code instead, which is why the code is always displayed too.
  verification_uri_complete?: string | null;
  verification_uri_guess: string;
  interval: number;
  expires_in: number;
}

export type BfabricDevicePoll =
  | { status: 'pending'; retry_in?: number }
  | ({ status: 'ok' } & LoginResponse);

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