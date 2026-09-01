require 'rails_helper'
# The controller requires this lazily, inside the LDAP branch, so the constant does
# not exist yet when the examples below set their expectations on it.
require 'net/ldap'

# B2 auth gateway — conformance with backend/swagger/v1/swagger.yaml
RSpec.describe 'Api::V1::Auth', type: :request do
  let(:password) { 'password123' }
  let!(:user) { create(:user, login: 'alice', password: password, password_confirmation: password) }
  let!(:project1) { create(:project, number: 1001) }
  let!(:project2) { create(:project, number: 1002) }

  before { mock_authentication_skipped(false) }
  # FGCZ (LDAP project resolver) is now loaded app-wide; stub it so project
  # resolution is deterministic in the test env instead of hitting real LDAP.
  before { allow(FGCZ).to receive(:get_user_projects2).and_return(%w[p1001 p1002]) }

  def body
    JSON.parse(response.body)
  end

  describe 'POST /api/v1/auth/login' do
    it 'authenticates with username and returns a TokenResponse + refresh cookie' do
      post '/api/v1/auth/login', params: { username: 'alice', password: password }

      expect(response).to have_http_status(:ok)
      expect(body['token_type']).to eq('bearer')
      expect(body['access_token']).to be_present
      expect(body['user']).to include('user_id' => user.id, 'login' => 'alice')
      expect(body['user']['projects']).to match_array([1001, 1002])

      # Refresh token is delivered as an HttpOnly cookie, never in the body.
      expect(body).not_to have_key('refresh_token')
      set_cookie = response.headers['Set-Cookie']
      expect(set_cookie).to match(/refresh_token=/)
      expect(set_cookie).to match(/HttpOnly/i)
      expect(set_cookie).to match(/SameSite=Strict/i)
      expect(RefreshToken.active.where(user_id: user.id).count).to eq(1)
    end

    it 'still accepts the legacy :login parameter' do
      post '/api/v1/auth/login', params: { login: 'alice', password: password }
      expect(response).to have_http_status(:ok)
    end

    # The LDAP branch used to create the local row "regardless of auto_create_user".
    # On 082 that is an INSERT into the live legacy production `users` table on
    # someone's first sign-in, from a node that is supposed to write nothing.
    context 'when LDAP authenticates a login that has no local user row' do
      let(:ldap) { instance_double(Net::LDAP) }

      before do
        allow(AuthenticationHelper).to receive(:ldap_auth_enabled?).and_return(true)
        allow(Net::LDAP).to receive(:new).and_return(ldap)
        allow(ldap).to receive(:bind_as).and_return(true)
      end

      it 'refuses instead of creating one when auto_create_user is false' do
        allow(AuthenticationHelper).to receive(:ldap_config).and_return('auto_create_user' => false)

        expect {
          post '/api/v1/auth/login', params: { username: 'newcomer', password: 'whatever' }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates one when auto_create_user is true' do
        allow(AuthenticationHelper).to receive(:ldap_config).and_return('auto_create_user' => true)

        expect {
          post '/api/v1/auth/login', params: { username: 'newcomer', password: 'whatever' }
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(User.find_by(login: 'newcomer')).to be_present
      end
    end

    # 082 runs against legacy production SUSHI's database, which has no
    # refresh_tokens table and must never gain one. Before this, a login there
    # raised on the INSERT and answered 500; now the login succeeds and simply
    # carries no refresh cookie. This is the property that makes the whole login
    # path write-free, which is in turn why the read-only gate lets it through.
    context 'when the refresh_tokens table is absent (082)' do
      before { allow(RefreshToken).to receive(:available?).and_return(false) }

      it 'still returns a usable access token and writes no refresh row' do
        expect {
          post '/api/v1/auth/login', params: { username: 'alice', password: password }
        }.not_to change(RefreshToken, :count)

        expect(response).to have_http_status(:ok)
        expect(body['access_token']).to be_present
        expect(body['user']).to include('user_id' => user.id, 'login' => 'alice')
        expect(response.headers['Set-Cookie'].to_s).not_to match(/refresh_token=/)
      end
    end

    it 'returns 401 on invalid credentials' do
      post '/api/v1/auth/login', params: { username: 'alice', password: 'wrong' }
      expect(response).to have_http_status(:unauthorized)
      expect(body['error']).to eq('invalid_credentials')
    end
  end

  describe 'POST /api/v1/auth/refresh' do
    it 'rotates the refresh token and issues a new access token' do
      post '/api/v1/auth/login', params: { username: 'alice', password: password }
      old_raw = cookies['refresh_token']
      expect(old_raw).to be_present

      post '/api/v1/auth/refresh'
      expect(response).to have_http_status(:ok)
      expect(body['access_token']).to be_present
      expect(body['user']).to include('user_id' => user.id, 'login' => 'alice')

      # Old token revoked (rotation); a new active token exists.
      expect(RefreshToken.find_active(old_raw)).to be_nil
      expect(RefreshToken.active.where(user_id: user.id).count).to eq(1)
      expect(cookies['refresh_token']).to be_present
      expect(cookies['refresh_token']).not_to eq(old_raw)
    end

    it 'detects refresh-token reuse and revokes all sessions' do
      post '/api/v1/auth/login', params: { username: 'alice', password: password }
      old_raw = cookies['refresh_token']

      post '/api/v1/auth/refresh' # rotates: old_raw now revoked, new token issued
      expect(response).to have_http_status(:ok)

      # Replay the already-revoked old token.
      cookies['refresh_token'] = old_raw
      post '/api/v1/auth/refresh'

      expect(response).to have_http_status(:unauthorized)
      expect(body['error']).to eq('invalid_refresh_token')
      # Reuse detection nukes every session for the user.
      expect(RefreshToken.active.where(user_id: user.id).count).to eq(0)
    end

    it 'returns 401 without a refresh cookie' do
      post '/api/v1/auth/refresh'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/auth/logout' do
    it 'revokes the current refresh token' do
      post '/api/v1/auth/login', params: { username: 'alice', password: password }
      raw = cookies['refresh_token']

      post '/api/v1/auth/logout'
      expect(response).to have_http_status(:ok)
      expect(RefreshToken.find_active(raw)).to be_nil
    end
  end

  describe 'POST /api/v1/auth/logout-all' do
    it 'revokes all sessions for the bearer-authenticated user' do
      RefreshToken.issue(user: user, ttl: 7.days)
      RefreshToken.issue(user: user, ttl: 7.days)

      post '/api/v1/auth/logout-all', headers: jwt_headers_for(user)
      expect(response).to have_http_status(:ok)
      expect(RefreshToken.active.where(user_id: user.id).count).to eq(0)
    end

    it 'requires a bearer token' do
      post '/api/v1/auth/logout-all'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/auth/me' do
    it 'returns the contract User for a valid bearer token' do
      get '/api/v1/auth/me', headers: jwt_headers_for(user)
      expect(response).to have_http_status(:ok)
      expect(body).to include('user_id' => user.id, 'login' => 'alice')
      expect(body['projects']).to match_array([1001, 1002])
    end

    it 'returns 401 without a token' do
      get '/api/v1/auth/me'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/auth/login_options' do
    it 'advertises the available auth methods (public)' do
      get '/api/v1/auth/login_options'
      expect(response).to have_http_status(:ok)
      expect(body).to include('ldap_auth', 'authentication_skipped')
    end
  end
end
