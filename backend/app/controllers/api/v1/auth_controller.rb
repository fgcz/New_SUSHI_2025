module Api
  module V1
    class AuthController < ApplicationController
      # Authentication controller skips JWT authentication
      skip_before_action :authenticate_jwt_token
      
      # JWT login
      def login
        user = User.find_by(login: params[:login]) || User.find_by(email: params[:login])
        
        if user&.valid_password?(params[:password])
          token = generate_jwt_token(user)
          render json: {
            token: token,
            user: {
              id: user.id,
              login: user.login,
              email: user.email
            },
            message: 'Login successful'
          }
        else
          render json: { error: 'Invalid credentials' }, status: :unauthorized
        end
      end
      
      # JWT register
      def register
        return render json: { error: 'Registration disabled' }, status: :forbidden unless AuthenticationHelper.standard_login_enabled? && AuthenticationHelper.config['standard_login']['allow_registration']
        
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
            user: {
              id: user.id,
              login: user.login,
              email: user.email
            },
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
          user: {
            id: user.id,
            login: user.login,
            email: user.email
          },
          valid: true
        }
      end
      
      private
      
      def generate_jwt_token(user)
        payload = {
          user_id: user.id,
          login: user.login,
          email: user.email,
          exp: JWT_EXPIRATION_TIME.to_i,
          iat: Time.current.to_i
        }
        
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