module AuthenticationHelpers
  def generate_jwt_token_for_user(user)
    payload = {
      user_id: user.id,
      login: user.login,
      email: user.email,
      exp: 24.hours.from_now.to_i,
      iat: Time.current.to_i
    }

    JWT.encode(payload, JWT_SECRET_KEY, JWT_ALGORITHM)
  end

  # For request specs: returns headers hash including Authorization
  def jwt_headers_for(user)
    token = generate_jwt_token_for_user(user)
    { 'Authorization' => "Bearer #{token}" }
  end

  def mock_authentication_skipped(skipped = true)
    allow(AuthenticationHelper).to receive(:authentication_skipped?).and_return(skipped)
  end

  def mock_ldap_auth_enabled(enabled = false)
    allow(AuthenticationHelper).to receive(:ldap_auth_enabled?).and_return(enabled)
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end


