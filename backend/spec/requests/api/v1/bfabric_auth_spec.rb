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

  # ------------------------------------------------------------------------------------
  # THE BROWSER LOGIN. The browser asks this backend to run the device flow on its behalf
  # and collects a finished SUSHI session. It never sees a B-Fabric token: that token is
  # LIMS-wide while the session it buys is not, so one XSS would otherwise cost the whole
  # LIMS instead of thirty minutes.
  # ------------------------------------------------------------------------------------
  describe 'browser device login' do
    def device_url = 'https://bfabric.example/device'
    def token_url  = 'https://bfabric.example/token'

    before do
      enable_oidc
      allow(BfabricOidc::JwksCache).to receive(:discovery).and_return(
        'device_authorization_endpoint' => device_url, 'token_endpoint' => token_url
      )
    end

    def stub_device_authorization(overrides = {})
      stub_request(:post, device_url).to_return(
        status: 200,
        body: { device_code: 'DEVICE-CODE-SECRET', user_code: 'ABCD-EFGH',
                verification_uri: 'https://bfabric.example/oauth/device.html',
                interval: 1, expires_in: 900 }.merge(overrides).to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    def stub_token(body)
      stub_request(:post, token_url).to_return(
        status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
      )
    end

    def start_login(query = '')
      stub_device_authorization
      get "/api/v1/auth/bfabric/device/start#{query}"
      JSON.parse(response.body)
    end

    describe 'starting' do
      it 'returns what the human needs to approve' do
        body = start_login
        expect(response).to have_http_status(:ok)
        expect(body['user_code']).to eq('ABCD-EFGH')
        expect(body['verification_uri']).to eq('https://bfabric.example/oauth/device.html')
        expect(body['handle']).to be_present
        expect(body['interval']).to eq(1)
      end

      # THE ONE THING THAT MUST NOT LEAK. Whoever holds the device_code can redeem the
      # login themselves at B-Fabric; the opaque handle is only meaningful to this node.
      it 'never returns the device_code' do
        expect(response.body).not_to include('DEVICE-CODE-SECRET') if start_login
        expect(start_login.keys).not_to include('device_code')
      end

      # B-Fabric does not send RFC 8628's verification_uri_complete (measured on both
      # instances), so we offer a constructed guess. If the approval page ignores the
      # parameter nothing breaks — the user types the code we also return.
      it 'offers a guessed prefill URL carrying the user code' do
        expect(start_login['verification_uri_guess'])
          .to eq('https://bfabric.example/oauth/device.html?user_code=ABCD-EFGH')
      end

      it 'asks for api:write only when the caller does' do
        start_login
        expect(a_request(:post, device_url)
                 .with { |r| !r.body.include?('api%3Awrite') }).to have_been_made

        start_login('?write=1')
        expect(a_request(:post, device_url)
                 .with { |r| r.body.include?('api%3Awrite') }).to have_been_made
      end

      it 'is 404 when the node has not enabled the browser login' do
        ENV['BFABRIC_OIDC_DEVICE_LOGIN'] = '0'
        BfabricOidc.reset!
        get '/api/v1/auth/bfabric/device/start'
        expect(response).to have_http_status(:not_found)
      ensure
        ENV.delete('BFABRIC_OIDC_DEVICE_LOGIN')
      end

      # This route is unauthenticated by necessity, so the only thing standing between it
      # and an unbounded table is this cap.
      it 'refuses with 503 rather than growing without limit' do
        stub_device_authorization
        stub_const('BfabricOidc::DeviceFlow::MAX_PENDING', 2)
        2.times { get '/api/v1/auth/bfabric/device/start' }
        get '/api/v1/auth/bfabric/device/start'
        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)['error']).to eq('too_many_logins_in_progress')
      end
    end

    describe 'polling' do
      it 'reports pending until the human approves' do
        handle = start_login['handle']
        stub_token(error: 'authorization_pending')
        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['status']).to eq('pending')
      end

      it 'issues a SUSHI session once approved, and returns no B-Fabric token' do
        handle = start_login['handle']
        stub_token(access_token: bfabric_token, token_type: 'Bearer', expires_in: 3600)

        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['status']).to eq('ok')
        expect(body['user']).to include('login' => 'masaomi')
        expect(decode_jwt_token(body['access_token'])['src']).to eq('bfabric')
        expect(response.body).not_to include(bfabric_token)
        expect(response.headers['Cache-Control']).to include('no-store')
      end

      # A handle that survived its own success could be replayed by anyone who saw it.
      it 'spends the handle: a second poll after success is refused' do
        handle = start_login['handle']
        stub_token(access_token: bfabric_token, token_type: 'Bearer')
        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }
        expect(response).to have_http_status(:ok)

        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to eq('device_code_expired')
      end

      it 'refuses an unknown handle without reaching B-Fabric' do
        get '/api/v1/auth/bfabric/device/poll', params: { handle: 'made-up' }
        expect(response).to have_http_status(:unauthorized)
        expect(a_request(:post, token_url)).not_to have_been_made
      end

      it 'refuses a request with no handle at all' do
        get '/api/v1/auth/bfabric/device/poll'
        expect(response).to have_http_status(:bad_request)
      end

      it 'reports a B-Fabric refusal without pretending the token was bad' do
        handle = start_login['handle']
        stub_token(error: 'access_denied')
        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }
        expect(JSON.parse(response.body)['error']).to eq('device_code_expired')
      end

      # The interval is enforced here, not trusted from the client: an unauthenticated
      # caller that ignored it would use this node to hammer B-Fabric.
      it 'enforces the poll interval server-side' do
        handle = start_login['handle']
        stub_token(error: 'authorization_pending')
        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }
        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }

        expect(a_request(:post, token_url)).to have_been_made.once
        expect(JSON.parse(response.body)['status']).to eq('pending')
        expect(JSON.parse(response.body)['retry_in']).to be_positive
      end

      it 'answers 503, not 401, when B-Fabric cannot be reached' do
        handle = start_login['handle']
        stub_request(:post, token_url).to_raise(Errno::ECONNREFUSED)
        get '/api/v1/auth/bfabric/device/poll', params: { handle: handle }
        expect(response).to have_http_status(:service_unavailable)
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
