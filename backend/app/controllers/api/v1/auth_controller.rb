module Api
  module V1
    class AuthController < ApplicationController
      # Session minting — the JWT, the refresh cookie and the User payload — lives in the
      # shared concern so the B-Fabric OIDC login converges on exactly this code rather
      # than growing a parallel one. It brings ProjectAuthorizable with it, which is what
      # supplies the User payload's project list (contract: User.projects).
      include SessionIssuing

      # Skip CSRF protection for API endpoints.
      skip_before_action :verify_authenticity_token
      # NOTE: we do NOT blanket-skip :authenticate_jwt_token here. The inherited
      # before_action self-skips public/cookie actions via skip_jwt_authentication?
      # (login, register, login_options, refresh, logout) and enforces a bearer
      # access token for the rest (me, logout-all, verify).

      # POST /api/v1/auth/login
      # Authenticate (LDAP or standard) and issue tokens.
      def login
        login_param = params[:username].presence || params[:login]
        password = params[:password]

        user = authenticate_login(login_param, password)
        return render json: { error: 'invalid_credentials', message: 'Invalid credentials' }, status: :unauthorized unless user

        issue_tokens_for(user)
        render json: token_response(user)
      end

      # POST /api/v1/auth/refresh
      # Rotate the refresh token (cookie) and issue a fresh access token.
      def refresh
        raw = cookies[:refresh_token]
        record = RefreshToken.find_active(raw)

        unless record
          # Reuse detection: a known but already-revoked token being replayed is
          # treated as theft -> revoke every session for that user.
          replayed = RefreshToken.find_any(raw)
          if replayed&.revoked?
            RefreshToken.revoke_all_for!(replayed.user)
            Rails.logger.warn("AuthController#refresh: revoked refresh token replayed for user_id=#{replayed.user_id}; revoked all sessions")
          end
          clear_refresh_cookie
          return render json: { error: 'invalid_refresh_token', message: 'Missing, invalid, or expired refresh token' }, status: :unauthorized
        end

        user = record.user
        RefreshToken.revoke!(raw)
        issue_tokens_for(user)
        render json: token_response(user)
      end

      # POST /api/v1/auth/logout
      # Revoke the current refresh token and clear the cookie.
      def logout
        RefreshToken.revoke!(cookies[:refresh_token]) if cookies[:refresh_token].present?
        clear_refresh_cookie
        render json: { message: 'Logged out successfully' }
      end

      # POST /api/v1/auth/logout-all
      # Revoke all refresh tokens for the current (bearer-authenticated) user.
      def logout_all
        count = RefreshToken.revoke_all_for!(current_user)
        clear_refresh_cookie
        render json: { message: "Logged out from #{count} session(s)" }
      end

      # GET /api/v1/auth/me
      # Current authenticated user (bearer access token required).
      def me
        render json: serialize_user(current_user)
      end

      # GET /api/v1/auth/login_options
      # Advertise available authentication methods (contract: LoginOptions).
      def login_options
        render json: {
          ldap_auth: AuthenticationHelper.ldap_auth_enabled?,
          # Kept in step with AuthenticationController#login_options, which is the one the
          # frontend calls. Two endpoints answer this question; updating only one is a
          # silent failure (the button simply never renders).
          bfabric_oidc: AuthenticationHelper.bfabric_oidc_enabled?,
          authentication_skipped: AuthenticationHelper.authentication_skipped?
        }
      end

      # POST /api/v1/auth/register
      def register
        return render json: { error: 'registration_disabled', message: 'Registration disabled' }, status: :forbidden unless AuthenticationHelper.standard_login_enabled? && AuthenticationHelper.config['standard_login']['allow_registration']
        return render json: { error: 'registration_disabled', message: 'Registration not available in legacy database mode' }, status: :forbidden if AuthenticationHelper.legacy_database?

        user = User.new(
          login: params[:login],
          email: params[:email],
          password: params[:password],
          password_confirmation: params[:password_confirmation]
        )

        if user.save
          issue_tokens_for(user)
          render json: token_response(user), status: :created
        else
          render json: { error: 'validation_error', errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/auth/verify
      # DEPRECATED: use GET /api/v1/auth/me instead. Retained for backward compatibility
      # with existing clients; not part of the frozen OpenAPI contract.
      def verify
        token = extract_token_from_header
        return render json: { valid: false, error: 'No token provided' }, status: :unauthorized unless token

        payload = decode_jwt_token(token)
        return render json: { valid: false, error: 'Invalid token' }, status: :unauthorized unless payload

        user = User.find_by(id: payload['user_id'])
        return render json: { valid: false, error: 'User not found' }, status: :unauthorized unless user

        render json: { user: serialize_user(user), valid: true }
      end

      private

      # ----- token issuance -------------------------------------------------
      #
      # issue_tokens_for / token_response / serialize_user / set_refresh_cookie /
      # clear_refresh_cookie / REFRESH_TTL now live in SessionIssuing (included above),
      # unchanged. They moved so the B-Fabric OIDC login can converge on them.

      # ----- credential authentication --------------------------------------

      def authenticate_login(login_param, password)
        if AuthenticationHelper.ldap_auth_enabled?
          user = authenticate_with_ldap(login_param, password)
          return user if user
        end

        if AuthenticationHelper.standard_login_enabled?
          user = if AuthenticationHelper.legacy_database?
                   User.find_by(login: login_param)
                 else
                   User.find_by(login: login_param) || User.find_by(email: login_param)
                 end
          return user if user&.valid_password?(password)
        end

        nil
      end

      def authenticate_with_ldap(login, password)
        return nil unless AuthenticationHelper.ldap_auth_enabled?

        begin
          begin
            require 'net/ldap'
          rescue LoadError => e
            Rails.logger.error "LDAP library not available: #{e.message}"
            return nil
          end

          # Load connection settings from config/ldap.yml
          ldap_cfg = YAML.load(ERB.new(File.read(Rails.root.join('config', 'ldap.yml'))).result, aliases: true)[Rails.env]
          host = ldap_cfg['host'] || 'fgcz-bfabric-ldap'
          port = ldap_cfg['port'] || 636
          base = ldap_cfg['base'] || 'dc=bfabric,dc=org'
          ssl  = ldap_cfg['ssl']
          verify_peer = ldap_cfg['ssl_verify']
          encryption = ssl ? :simple_tls : nil
          verify_mode = verify_peer ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE

          user = User.find_by(login: login)

          ldap = Net::LDAP.new(
            host: host,
            port: port,
            base: base,
            encryption: encryption,
            verify_mode: verify_mode
          )

          if ldap.bind_as(base: "cn=#{login},ou=Users,dc=bfabric,dc=org", password: password)
            # A first-time login used to create the local row "regardless of
            # auto_create_user", ignoring the setting in authentication.yml, which is
            # false. On 082 that would INSERT into the live legacy production `users`
            # table (2203 rows) on someone's first sign-in — a write nobody asked for,
            # from a node whose whole posture is that it writes nothing. The setting is
            # now honoured.
            #
            # Consequence worth knowing: with creation disabled, a real employee whose
            # password is correct but who has no row yet is refused like a bad password.
            # The log line below is the only place that distinction is visible.
            unless user
              unless AuthenticationHelper.ldap_config['auto_create_user']
                Rails.logger.warn("LDAP bind succeeded for #{login} but no local user row exists and auto_create_user is false; refusing")
                return nil
              end

              user_attrs = { login: login }
              unless AuthenticationHelper.legacy_database?
                user_attrs[:email] = "#{login}@bfabric.org"
                user_attrs[:password] = Devise.friendly_token[0, 20]
              end
              user = User.create!(user_attrs)
            end

            return user
          end

          nil
        rescue => e
          Rails.logger.error "LDAP authentication error: #{e.message}"
          nil
        end
      end
    end
  end
end
