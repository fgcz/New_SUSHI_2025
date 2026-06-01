module Api
  module V1
    class AuthController < ApplicationController
      # Authentication controller skips JWT authentication
      skip_before_action :authenticate_jwt_token
      # Skip CSRF protection for API endpoints
      skip_before_action :verify_authenticity_token
      
      # JWT login with LDAP support
      def login
        login_param = params[:login]
        password = params[:password]
        
        # Try LDAP authentication first if enabled
        if AuthenticationHelper.ldap_auth_enabled?
          user = authenticate_with_ldap(login_param, password)
          if user
            token = generate_jwt_token(user)
            render json: {
              token: token,
              user: serialize_user(user),
              message: 'LDAP login successful'
            }
            return
          end
        end
        
        # Fallback to standard authentication if LDAP fails or is disabled
        if AuthenticationHelper.standard_login_enabled?
          # In legacy mode, only search by login (email column doesn't exist)
          user = if AuthenticationHelper.legacy_database?
                   User.find_by(login: login_param)
                 else
                   User.find_by(login: login_param) || User.find_by(email: login_param)
                 end
          
          if user&.valid_password?(password)
            token = generate_jwt_token(user)
            render json: {
              token: token,
              user: serialize_user(user),
              message: 'Standard login successful'
            }
            return
          end
        end
        
        # Authentication failed
        render json: { error: 'Invalid credentials' }, status: :unauthorized
      end
      
      # JWT register
      def register
        return render json: { error: 'Registration disabled' }, status: :forbidden unless AuthenticationHelper.standard_login_enabled? && AuthenticationHelper.config['standard_login']['allow_registration']
        return render json: { error: 'Registration not available in legacy database mode' }, status: :forbidden if AuthenticationHelper.legacy_database?
        
        user = User.new(
          login: params[:login],
          email: params[:email],
          password: params[:password],
          password_confirmation: params[:password_confirmation]
        )
        
        if user.save
          token = generate_jwt_token(user)
          render json: {
            token: token,
            user: serialize_user(user),
            message: 'Registration successful'
          }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # JWT logout (client-side token removal)
      def logout
        # JWT is stateless, so nothing to do on server side
        # Client side removes the token
        render json: { message: 'Logout successful' }
      end
      
      # Verify JWT token
      def verify
        token = extract_token_from_header
        return render json: { valid: false, error: 'No token provided' }, status: :unauthorized unless token
        
        payload = decode_jwt_token(token)
        return render json: { valid: false, error: 'Invalid token' }, status: :unauthorized unless payload
        
        user = User.find_by(id: payload['user_id'])
        return render json: { valid: false, error: 'User not found' }, status: :unauthorized unless user
        
        render json: {
          user: serialize_user(user),
          valid: true
        }
      end
      
      private
      
      # Serialize user data, excluding email in legacy database mode
      def serialize_user(user)
        data = { id: user.id, login: user.login }
        data[:email] = user.email unless AuthenticationHelper.legacy_database?
        data
      end
      
      def authenticate_with_ldap(login, password)
        return nil unless AuthenticationHelper.ldap_auth_enabled?
        
        # Use direct LDAP authentication
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
          
          # Try to find existing user
          user = User.find_by(login: login)
          
          # Try to authenticate with LDAP directly
          ldap = Net::LDAP.new(
            host: host,
            port: port,
            base: base,
            encryption: encryption,
            verify_mode: verify_mode
          )
          
          # Try to bind with user credentials
          if ldap.bind_as(
            base: "cn=#{login},ou=Users,dc=bfabric,dc=org",
            password: password
          )
            # LDAP authentication successful
            
            # If user doesn't exist, create user (regardless of auto_create_user setting)
            if !user
              user_attrs = { login: login }
              # Only set email/password if not in legacy database mode
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
      
      def generate_jwt_token(user)
        payload = {
          user_id: user.id,
          login: user.login,
          exp: JWT_EXPIRATION_TIME.to_i,
          iat: Time.current.to_i
        }
        # Include email only if not in legacy database mode
        payload[:email] = user.email unless AuthenticationHelper.legacy_database?
        
        JWT.encode(payload, JWT_SECRET_KEY, JWT_ALGORITHM)
      end
      
      def extract_token_from_header
        auth_header = request.headers['Authorization']
        return nil unless auth_header
        
        # Expect Bearer token format
        token = auth_header.split(' ').last
        token if token.present?
      end
      
      def decode_jwt_token(token)
        decoded = JWT.decode(token, JWT_SECRET_KEY, true, { algorithm: JWT_ALGORITHM })
        decoded[0]
      rescue JWT::DecodeError => e
        Rails.logger.error "JWT decode error: #{e.message}"
        nil
      end
    end
  end
end 