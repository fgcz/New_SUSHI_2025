# JWT Configuration
JWT_SECRET_KEY = ENV.fetch('JWT_SECRET_KEY') { Rails.application.secret_key_base }
JWT_ALGORITHM = 'HS256'
JWT_EXPIRATION_TIME = 24.hours.from_now

# JWT token generation
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

# JWT token decoding
def decode_jwt_token(token)
  decoded = JWT.decode(token, JWT_SECRET_KEY, true, { algorithm: JWT_ALGORITHM })
  decoded[0]
rescue JWT::DecodeError => e
  Rails.logger.error "JWT decode error: #{e.message}"
  nil
end 