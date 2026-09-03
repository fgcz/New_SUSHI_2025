# frozen_string_literal: true

require 'rails_helper'

# generate_jwt_token gained an optional second argument so a login that did NOT come from a
# password can record its provenance in the token. Everything here is about making sure that
# widening cannot be turned against the issuer.
RSpec.describe 'generate_jwt_token' do
  let(:user) { User.create!(login: 'masaomi', email: 'masaomi@example.com', password: 'password123') }

  def decode(token)
    JWT.decode(token, JWT_SECRET_KEY, true, { algorithm: JWT_ALGORITHM }).first
  end

  it 'still works with one argument, exactly as every existing call site uses it' do
    payload = decode(generate_jwt_token(user))
    expect(payload).to include('user_id' => user.id, 'login' => 'masaomi', 'type' => 'access')
    expect(payload.keys).not_to include('src')
  end

  it 'carries extra claims through into the token' do
    payload = decode(generate_jwt_token(user, src: 'bfabric', scope: 'openid api:read'))
    expect(payload['src']).to eq('bfabric')
    expect(payload['scope']).to eq('openid api:read')
  end

  # The claims this issuer owns must not be reachable from a caller. Without this, a
  # widened call site could mint a refresh-typed token, extend its own lifetime, or issue a
  # session for a different user.
  it 'refuses to let extra claims overwrite the claims the issuer owns' do
    payload = decode(
      generate_jwt_token(user,
                         type: 'refresh',
                         user_id: 999_999,
                         login: 'someone-else',
                         exp: Time.now.to_i + 10_000_000)
    )

    expect(payload['type']).to eq('access')
    expect(payload['user_id']).to eq(user.id)
    expect(payload['login']).to eq('masaomi')
    expect(payload['exp']).to be < (Time.now.to_i + 10_000_000)
  end

  it 'accepts string keys as well as symbols' do
    payload = decode(generate_jwt_token(user, 'src' => 'bfabric'))
    expect(payload['src']).to eq('bfabric')
  end

  it 'produces a token decode_jwt_token accepts, so nothing downstream changes' do
    expect(decode_jwt_token(generate_jwt_token(user, src: 'bfabric'))).to include('src' => 'bfabric')
  end
end
