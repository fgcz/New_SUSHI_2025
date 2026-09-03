# frozen_string_literal: true

require 'rails_helper'

# GET /api/v1/auth/bfabric/session — the one route that accepts a B-Fabric token.
#
# The headless entry point: an agent runs the device-code flow against B-Fabric itself
# (public client `CLI`, no registration) and exchanges the result here for the SUSHI JWT
# the rest of the system already speaks.
RSpec.describe 'B-Fabric OIDC session exchange', type: :request do
  def issuer   = 'https://bfabric.example/bfabric'
  def audience = 'bfabric-api'
  def endpoint = '/api/v1/auth/bfabric/session'

  def oidc_vars
    %w[BFABRIC_OIDC_ENABLED BFABRIC_OIDC_BASE_URL BFABRIC_OIDC_AUDIENCE
       BFABRIC_OIDC_ALLOWED_CLIENT_IDS BFABRIC_OIDC_REQUIRED_SCOPE]
  end

  around do |example|
    saved = oidc_vars.to_h { |v| [v, ENV[v]] }
    oidc_vars.each { |v| ENV.delete(v) }
    BfabricOidc.reset!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      BfabricOidc.reset!
    end
  end

  def enable_oidc
    ENV['BFABRIC_OIDC_ENABLED']  = '1'
    ENV['BFABRIC_OIDC_BASE_URL'] = issuer
    ENV['BFABRIC_OIDC_AUDIENCE'] = audience
    BfabricOidc.reset!
    allow(BfabricOidc::JwksCache).to receive(:expected_issuer).and_return(issuer)
    allow(BfabricOidc::JwksCache).to receive(:jwks_loader)
      .and_return(->(_opts = {}) { BfabricOidcTestKeys.jwks_hash })
  end

  def bfabric_token(sub: 'masaomi', scope: 'openid profile api:read', **overrides)
    now = Time.now.to_i
    BfabricOidcTestKeys.sign(
      { 'iss' => issuer, 'aud' => audience, 'sub' => sub, 'scope' => scope,
        'iat' => now, 'exp' => now + 3600 }.merge(overrides.transform_keys(&:to_s))
    )
  end

  def get_session(token)
    get endpoint, headers: { 'Authorization' => "Bearer #{token}" }
  end

  let!(:user) { User.create!(login: 'masaomi', email: 'masaomi@example.com', password: 'password123') }

  describe 'when the feature is not enabled on this node' do
    # 404, not 403: the route should look like it does not exist. The 082 gate check
    # asserts exactly this, which is how it can tell "deployed but off" from "restarted
    # with the feature on" without a credential.
    it 'answers 404 and reveals nothing' do
      get_session(bfabric_token)
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('bfabric_oidc_disabled')
    end
  end

  describe 'when it is enabled' do
    before { enable_oidc }

    it 'exchanges a valid B-Fabric token for a SUSHI JWT that the rest of the API accepts' do
      get_session(bfabric_token)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['token_type']).to eq('bearer')
      expect(body['user']).to include('login' => 'masaomi', 'user_id' => user.id)
      expect(body['granted_scopes']).to include('api:read')

      # The whole point: the minted token is an ORDINARY SUSHI session token. Nothing
      # downstream can tell it apart from one issued by the password login.
      payload = decode_jwt_token(body['access_token'])
      expect(payload['user_id']).to eq(user.id)
      expect(payload['login']).to eq('masaomi')
      expect(payload['type']).to eq('access')
    end

    it 'records the session provenance and granted scopes in the JWT, not in the response' do
      get_session(bfabric_token(scope: 'openid api:read api:write'))
      payload = decode_jwt_token(JSON.parse(response.body)['access_token'])
      expect(payload['src']).to eq('bfabric')
      expect(payload['scope']).to include('api:write')
    end

    # RFC 6749 §5.1 — a response carrying a token must not be cached.
    it 'forbids caching of the response' do
      get_session(bfabric_token)
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    # THE LOAD-BEARING SPEC. This design's central safety claim is that the endpoint adds
    # nothing to Middleware::SushiReadOnlyGuard::NO_WRITE_PATHS because it never writes.
    # Do not delete this: row counts cannot see an UPDATE, so a later "parity" patch
    # adding sign_in bookkeeping here would break read_only on 082 with nothing failing.
    it 'performs NO database write of any kind' do
      writes = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        sql = payload[:sql].to_s
        writes << sql if sql.match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i)
      end

      begin
        get_session(bfabric_token)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      expect(writes).to be_empty, "expected no writes, got:\n#{writes.join("\n")}"
    end

    it 'never issues a refresh token, so the absent refresh_tokens table is irrelevant' do
      get_session(bfabric_token)
      expect(response.cookies['refresh_token']).to be_nil
    end

    describe 'refusals' do
      it 'refuses a request with no bearer at all' do
        get endpoint
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to eq('missing_bearer')
      end

      # Distinguishable reasons are the difference between a five-minute fix and an
      # afternoon: an agent must be able to tell "my token expired" from "this node does
      # not trust my issuer".
      it 'reports a distinguishable reason for each way a token can be bad' do
        {
          'expired' => bfabric_token(exp: Time.now.to_i - 120),
          'bad_issuer' => bfabric_token(iss: 'https://evil.example'),
          'bad_audience' => bfabric_token(aud: 'another-app'),
          'missing_scope' => bfabric_token(scope: 'openid'),
          'at_hash_present' => bfabric_token(at_hash: 'x'),
          'malformed' => 'not-a-jwt'
        }.each do |expected_reason, token|
          get_session(token)
          expect(response).to have_http_status(:unauthorized)
          body = JSON.parse(response.body)
          expect(body['error']).to eq('invalid_bfabric_token')
          expect(body['reason']).to eq(expected_reason)
        end
      end

      # auto_create_user is false and INSERT is forbidden on the production node, so a
      # person B-Fabric knows but SUSHI does not is refused — with a message that says so
      # rather than reading as a credential failure.
      it 'refuses a verified login that has no SUSHI user row, and does not create one' do
        expect { get_session(bfabric_token(sub: 'nobody')) }.not_to change(User, :count)
        expect(response).to have_http_status(:unauthorized)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('unknown_user')
        expect(body['message']).to include('administrator')
      end

      # A network fault is not an authentication failure, and answering 401 would send
      # people to re-authenticate pointlessly.
      it 'answers 503, not 401, when B-Fabric itself cannot be reached' do
        allow(BfabricOidc::JwksCache).to receive(:expected_issuer)
          .and_raise(BfabricOidc::Unreachable, 'connection refused')
        get_session(bfabric_token)
        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)['error']).to eq('bfabric_unreachable')
      end

      # JwtAuthenticatable#extract_token_from_header takes the last whitespace-separated
      # word and so accepts `Authorization: Basic <jwt>`. This controller anchors on the
      # scheme; a new credential family should not inherit that laxity.
      it 'ignores a credential presented under the wrong scheme' do
        get endpoint, headers: { 'Authorization' => "Basic #{bfabric_token}" }
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to eq('missing_bearer')
      end
    end
  end

  describe 'advertising the method' do
    it 'is announced on BOTH login_options endpoints, or the button never appears' do
      enable_oidc
      get '/auth/login_options'
      expect(JSON.parse(response.body)['bfabric_oidc']).to be(true)

      get '/api/v1/auth/login_options'
      expect(JSON.parse(response.body)['bfabric_oidc']).to be(true)
    end

    it 'is announced as false when the node has not enabled it' do
      get '/auth/login_options'
      expect(JSON.parse(response.body)['bfabric_oidc']).to be(false)
    end
  end
end
