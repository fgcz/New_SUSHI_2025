require 'rails_helper'

# End-to-end behaviour of the ENV-provisioned credential across every surface.
# The point of these examples is that the credential buys READ access and nothing
# else: the production node it exists for must not be writable through it.
RSpec.describe 'ENV-provisioned API token across surfaces', type: :request do
  def bearer(raw) = { 'Authorization' => "Bearer #{raw}" }
  def body = JSON.parse(response.body)

  let(:raw) { 'fixture-raw-bearer-value-not-a-real-token' }

  let!(:p1001)  { create(:project, number: 1001) }
  let!(:p2002)  { create(:project, number: 2002) }
  let!(:ds1001) { create(:data_set, project: p1001, user: nil) }
  let!(:ds2002) { create(:data_set, project: p2002, user: nil) }

  around do |example|
    saved = EnvApiToken::VARS.to_h { |v| [v, ENV[v]] }
    ENV[EnvApiToken::DIGEST_VAR] = Digest::SHA256.hexdigest(raw)
    ENV[EnvApiToken::SCOPE_VAR]  = '1001'
    ENV[EnvApiToken::NAME_VAR]   = 'chain-082'
    EnvApiToken.reload!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      EnvApiToken.reload!
    end
  end

  describe 'read access on /api/v1, scoped to the configured projects' do
    it 'lists only the credential’s projects and attributes it by name' do
      get '/api/v1/projects', headers: bearer(raw)
      expect(response).to have_http_status(:ok)
      expect(body['projects'].map { |p| p['number'] }).to eq([1001])
      expect(body['current_user']).to eq('apitoken:chain-082')
    end

    it 'reads an in-scope dataset (200) and forbids an out-of-scope one (403)' do
      get "/api/v1/datasets/#{ds1001.id}", headers: bearer(raw)
      expect(response).to have_http_status(:ok)

      get "/api/v1/datasets/#{ds2002.id}", headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
    end

    it 'scopes the dataset index' do
      get '/api/v1/datasets', headers: bearer(raw)
      ids = body['datasets'].map { |d| d['id'] }
      expect(ids).to include(ds1001.id)
      expect(ids).not_to include(ds2002.id)
    end
  end

  describe 'write authority' do
    # The credential is read-only by construction, so this holds even with the
    # write policy wide open — it does not depend on SUSHI_READ_ONLY being set.
    it 'refuses a job submission for an IN-scope dataset (403, read-only token)' do
      post '/api/v1/jobs',
           params: { job: { dataset_id: ds1001.id, app_name: 'Fastqc' } },
           headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
      expect(body['message']).to match(/read-only/i)
      # Must NOT point the operator at `grant_write ID=` for a credential that has
      # no row to grant anything to — least of all on the production node, where
      # api_tokens may not be written at all.
      expect(body['message']).not_to include('grant_write')
      expect(body['message']).to include(EnvApiToken::NAME_VAR)
    end

    it 'still points a DB token at the rake task, with its real id' do
      db_raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])
      post '/api/v1/jobs',
           params: { job: { dataset_id: ds1001.id, app_name: 'Fastqc' } },
           headers: bearer(db_raw)
      expect(response).to have_http_status(:forbidden)
      expect(body['message']).to include("grant_write ID=#{db_token.id}")
    end

    it 'refuses a dataset import (403)' do
      post '/api/v1/datasets',
           params: { data_set: { name: 'x', project_id: p1001.id } },
           headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses registration on the /v1 surface (403)' do
      post '/v1/datasets/register', params: {}.to_json,
           headers: bearer(raw).merge('CONTENT_TYPE' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses deregistration on the /v1 surface (403)' do
      delete "/v1/datasets/#{ds1001.id}", headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # INV-10 — a project-scoped credential must not reach the system-wide bridge.
  describe 'the /internal machine bridge' do
    it 'rejects the ENV credential (403): it is static, not machine' do
      get '/internal/legacy/jobs', params: { status: 'CREATED' }, headers: bearer(raw)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'a wrong bearer value' do
    it 'does not authenticate as the ENV credential' do
      get '/api/v1/projects', headers: bearer('not-the-token')
      # Falls through to the ordinary (non-token) path rather than being granted
      # the credential's scope: the credential's projects must not leak.
      expect(body['current_user']).not_to eq('apitoken:chain-082')
    end
  end

  describe 'reading the live /v1 surface' do
    it 'authenticates a GET that the DB has no row for' do
      get "/v1/datasets/#{ds1001.id}", headers: bearer(raw)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
