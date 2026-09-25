require 'rails_helper'

# SUSHI_ENV_TOKEN_SCOPE=all across the surfaces a read credential can reach. The
# wider scope must buy READ access to every project and nothing else: no write,
# and no entry to the system-wide /internal bridge.
RSpec.describe 'ENV-provisioned API token with SCOPE=all', type: :request do
  def bearer(raw) = { 'Authorization' => "Bearer #{raw}" }
  def body = JSON.parse(response.body)
  # The token gate answered, not the Rack write guard (pinned open below).
  def token_denial? = body['error'] == 'action not permitted for this token'

  let(:raw) { 'fixture-raw-bearer-value-not-a-real-token' }

  let!(:p1001)  { create(:project, number: 1001) }
  let!(:p2002)  { create(:project, number: 2002) }
  let!(:ds1001) { create(:data_set, project: p1001, user: nil) }
  let!(:ds2002) { create(:data_set, project: p2002, user: nil) }

  # SUSHI_WRITE_POLICY is pinned to `full` so the Rack write guard lets every
  # write through: a 403 below can then only come from the token itself.
  around do |example|
    saved = EnvApiToken::VARS.to_h { |v| [v, ENV[v]] }
    saved_policy = ENV['SUSHI_WRITE_POLICY']
    ENV['SUSHI_WRITE_POLICY'] = 'full'
    EnvApiToken::VARS.each { |v| ENV.delete(v) }
    ENV[EnvApiToken::DIGEST_VAR] = Digest::SHA256.hexdigest(raw)
    ENV[EnvApiToken::SCOPE_VAR]  = 'all'
    ENV[EnvApiToken::NAME_VAR]   = 'omakase-082'
    EnvApiToken.reload!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      saved_policy.nil? ? ENV.delete('SUSHI_WRITE_POLICY') : ENV['SUSHI_WRITE_POLICY'] = saved_policy
      EnvApiToken.reload!
    end
  end

  describe 'read access' do
    it 'lists every project and attributes the caller by name' do
      get '/api/v1/projects', headers: bearer(raw)
      expect(response).to have_http_status(:ok)
      expect(body['projects'].map { |p| p['number'] }).to contain_exactly(1001, 2002)
      expect(body['current_user']).to eq('apitoken:omakase-082')
    end

    # The call OMAKASE makes to find an order's dataset; with a numeric scope it
    # was the one that answered 403 "Project not accessible" on a real order.
    it 'lists the datasets of any project' do
      [[1001, ds1001], [2002, ds2002]].each do |number, ds|
        get "/api/v1/projects/#{number}/datasets", headers: bearer(raw)
        expect(response).to have_http_status(:ok)
        expect(body['datasets'].map { |d| d['id'] }).to include(ds.id)
      end
    end

    it 'reads a project created after boot, without a restart' do
      p3003 = create(:project, number: 3003)
      ds3003 = create(:data_set, project: p3003, user: nil)
      get "/api/v1/projects/3003/datasets", headers: bearer(raw)
      expect(response).to have_http_status(:ok)
      expect(body['datasets'].map { |d| d['id'] }).to include(ds3003.id)
    end

    it 'reads any dataset by id' do
      [ds1001, ds2002].each do |ds|
        get "/api/v1/datasets/#{ds.id}", headers: bearer(raw)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # On the production node these would load every dataset in one request.
  describe 'the unbounded list endpoints' do
    it 'refuses GET /api/v1/datasets and points at the per-project listing' do
      get '/api/v1/datasets', headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)
      expect(body['message']).to include('/api/v1/projects/:number/datasets')
    end

    it 'refuses GET /api/v1/jobs' do
      get '/api/v1/jobs', headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)
    end

    it 'leaves both endpoints to a numerically scoped credential as before' do
      ENV[EnvApiToken::SCOPE_VAR] = '1001'
      EnvApiToken.reload!
      get '/api/v1/datasets', headers: bearer(raw)
      expect(response).to have_http_status(:ok)
      expect(body['datasets'].map { |d| d['id'] }).to eq([ds1001.id])
      get '/api/v1/jobs', headers: bearer(raw)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'write authority' do
    it 'refuses a job submission (403, read-only token)' do
      post '/api/v1/jobs',
           params: { job: { dataset_id: ds1001.id, app_name: 'Fastqc' } },
           headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)
      expect(body['message']).to match(/read-only/i)
    end

    it 'refuses a dataset import (403)' do
      post '/api/v1/datasets',
           params: { data_set: { name: 'x', project_id: p1001.id } },
           headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)
    end

    it 'refuses registration and deregistration on the /v1 surface (403)' do
      post '/v1/datasets/register', params: {}.to_json,
           headers: bearer(raw).merge('CONTENT_TYPE' => 'application/json')
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)

      delete "/v1/datasets/#{ds1001.id}", headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
      expect(token_denial?).to be(true)
    end
  end

  describe 'the /internal machine bridge' do
    it 'rejects the credential (403): all-projects is still static, not machine' do
      get '/internal/legacy/jobs', params: { status: 'CREATED' }, headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
