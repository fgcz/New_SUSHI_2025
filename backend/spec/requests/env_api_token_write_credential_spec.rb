require 'rails_helper'

# The 082 cutover turns on TWO independent gates, and this file is the executable
# statement that both must be open before anything can be written:
#
#   gate 1  Middleware::SushiReadOnlyGuard  (SUSHI_WRITE_POLICY)
#   gate 2  ApiToken#can_write?             (which bearer value was presented)
#
# Each denial is attributed to its own gate by the response body, because during a
# cutover "403" on its own is the least useful thing a log can say: the operator
# needs to know WHICH gate refused before deciding what to change.
RSpec.describe 'ENV write credential and the write policy', type: :request do
  def bearer(raw) = { 'Authorization' => "Bearer #{raw}" }
  def body = JSON.parse(response.body)

  let(:read_raw)  { 'fixture-read-bearer-value-not-a-real-token' }
  let(:write_raw) { 'fixture-write-bearer-value-not-a-real-token' }

  let!(:p1001)  { create(:project, number: 1001) }
  let!(:ds1001) { create(:data_set, project: p1001, user: nil) }

  # A gate denial, told apart by who answered.
  def rack_denial? = %w[read_only additive].include?(body['error'])
  def token_denial? = body['error'] == 'action not permitted for this token'

  around do |example|
    saved = EnvApiToken::VARS.to_h { |v| [v, ENV[v]] }
    saved_policy = ENV['SUSHI_WRITE_POLICY']

    ENV[EnvApiToken::DIGEST_VAR] = Digest::SHA256.hexdigest(read_raw)
    ENV[EnvApiToken::SCOPE_VAR]  = '1001'
    ENV[EnvApiToken::NAME_VAR]   = 'chain-082'
    ENV[EnvApiToken::WRITE_DIGEST_VAR] = Digest::SHA256.hexdigest(write_raw)
    ENV[EnvApiToken::WRITE_SCOPE_VAR]  = '1001'
    ENV[EnvApiToken::WRITE_NAME_VAR]   = 'cutover-082'
    EnvApiToken.reload!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      saved_policy.nil? ? ENV.delete('SUSHI_WRITE_POLICY') : ENV['SUSHI_WRITE_POLICY'] = saved_policy
      EnvApiToken.reload!
    end
  end

  # An app name that resolves to nothing, so the controller is reached and fails
  # THERE — without submitting a job to a scheduler from a spec.
  def submit(raw)
    post '/api/v1/jobs',
         params: { job: { dataset_id: ds1001.id, app_name: 'NoSuchAppExistsHere' } },
         headers: bearer(raw)
  end

  # Positive proof of gate passage. Asserting merely "not a gate denial" would be
  # satisfied by ANY other 403 — including the project-scope denial — so it would
  # stay green if a gate started rejecting for the wrong reason. Only code
  # downstream of both gates can produce this 422.
  def expect_reached_the_controller
    expect(response).to have_http_status(:unprocessable_entity)
    expect(body['errors'].join).to include('Application not found')
  end

  describe 'gate 2 alone (write policy open, as on 083)' do
    it 'lets the WRITE credential past the token gate' do
      submit(write_raw)
      expect_reached_the_controller
    end

    it 'still refuses the READ credential, and says so as the token gate' do
      submit(read_raw)
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)
      expect(body['message']).to match(/read-only/i)
      expect(body['message']).to include(EnvApiToken::WRITE_DIGEST_VAR)
      expect(body['message']).not_to include('grant_write')
    end
  end

  describe 'gate 1 alone (write credential presented, policy closed)' do
    it 'refuses the WRITE credential under read_only, and says so as the write policy' do
      ENV['SUSHI_WRITE_POLICY'] = 'read_only'
      submit(write_raw)

      expect(response).to have_http_status(:forbidden)
      expect(rack_denial?).to be(true)
      expect(body['error']).to eq('read_only')
      expect(body['message']).to match(/write policy/i)
    end

    it 'refuses a DELETE even under additive — a writer is not a deleter' do
      ENV['SUSHI_WRITE_POLICY'] = 'additive'
      delete "/v1/datasets/#{ds1001.id}", headers: bearer(write_raw)

      expect(response).to have_http_status(:forbidden)
      expect(body['error']).to eq('additive')
    end
  end

  describe 'both gates open — the actual cutover configuration' do
    before { ENV['SUSHI_WRITE_POLICY'] = 'additive' }

    it 'lets the WRITE credential through to the controller' do
      submit(write_raw)
      expect_reached_the_controller
    end

    # The property the split exists for: opening the policy does NOT promote the
    # credential an agent reads production with.
    it 'STILL refuses the READ credential' do
      submit(read_raw)
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)
    end
  end

  describe 'the write credential does not widen anything else' do
    before { ENV['SUSHI_WRITE_POLICY'] = 'additive' }

    it 'is still project-scoped' do
      other = create(:data_set, project: create(:project, number: 2002), user: nil)
      post '/api/v1/jobs',
           params: { job: { dataset_id: other.id, app_name: 'Fastqc' } },
           headers: bearer(write_raw)

      expect(response).to have_http_status(:forbidden)
      # Denied by project scope, not by either write gate.
      expect(rack_denial?).to be(false)
      expect(token_denial?).to be(false)
    end

    it 'is still rejected by the /internal machine bridge: it is static, not machine' do
      get '/internal/legacy/jobs', params: { status: 'CREATED' }, headers: bearer(write_raw)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is attributed to its own name, so production rows are distinguishable' do
      get '/api/v1/projects', headers: bearer(write_raw)
      expect(body['current_user']).to eq('apitoken:cutover-082')

      get '/api/v1/projects', headers: bearer(read_raw)
      expect(body['current_user']).to eq('apitoken:chain-082')
    end
  end
end
