require 'rails_helper'

# SUSHI_API_TOKEN-guarded basic operations: a bearer ApiToken authenticates the
# JWT-based /api/v1 surface (headless, no UI), scoped to the token's projects.
RSpec.describe 'API v1 basic ops via SUSHI_API_TOKEN', type: :request do
  def bearer(raw) = { 'Authorization' => "Bearer #{raw}" }
  def body = JSON.parse(response.body)

  let!(:p1001)  { create(:project, number: 1001) }
  let!(:p2002)  { create(:project, number: 2002) }
  let!(:ds1001) { create(:data_set, project: p1001, user: nil) }
  let!(:ds2002) { create(:data_set, project: p2002, user: nil) }

  describe 'static token (scope [1001])' do
    let(:token) { ApiToken.issue(name: 'chain', scope: [1001])[0] }

    it 'lists only the token’s projects' do
      get '/api/v1/projects', headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(body['projects'].map { |p| p['number'] }).to eq([1001])
      expect(body['current_user']).to eq('apitoken:chain')
    end

    it 'lists datasets of an in-scope project (200) and forbids out-of-scope (403)' do
      get '/api/v1/projects/1001/datasets', headers: bearer(token)
      expect(response).to have_http_status(:ok)
      get '/api/v1/projects/2002/datasets', headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
    end

    it 'scopes the dataset index to the token’s projects' do
      get '/api/v1/datasets', headers: bearer(token)
      ids = body['datasets'].map { |d| d['id'] }
      expect(ids).to include(ds1001.id)
      expect(ids).not_to include(ds2002.id)
    end

    it 'forbids showing an out-of-scope dataset' do
      get "/api/v1/datasets/#{ds2002.id}", headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
    end

    it 'scopes the job index and forbids an out-of-scope job show' do
      j1 = create(:job, status: 'COMPLETED', data_set: ds1001)
      j2 = create(:job, status: 'COMPLETED', data_set: ds2002)
      get '/api/v1/jobs', headers: bearer(token)
      ids = body['jobs'].map { |j| j['id'] }
      expect(ids).to include(j1.id)
      expect(ids).not_to include(j2.id)
      get "/api/v1/jobs/#{j2.id}", headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids submitting a job for an out-of-scope dataset (before the service runs)' do
      post '/api/v1/jobs', params: { job: { dataset_id: ds2002.id, app_name: 'Fastqc' } }
      # sanity: without a token in test this would behave differently; assert the token path 403s
      post '/api/v1/jobs', params: { job: { dataset_id: ds2002.id, app_name: 'Fastqc' } }, headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'machine token' do
    it 'is rejected on the basic-ops surface (403)' do
      machine = ApiToken.issue(name: 'jm', principal: 'machine')[0]
      get '/api/v1/projects', headers: bearer(machine)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user token' do
    let(:token) { ApiToken.issue(name: 'u', principal: 'user', login: 'masaomi', ttl_days: 30)[0] }

    it 'resolves projects live from FGCZ for the token login' do
      allow(FGCZ).to receive(:get_user_projects2).with('masaomi').and_return(['p1001'])
      get '/api/v1/projects', headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(body['projects'].map { |p| p['number'] }).to eq([1001])
      expect(body['current_user']).to eq('masaomi')
    end

    it 'returns 503 when the FGCZ resolver is unavailable' do
      allow(FGCZ).to receive(:get_user_projects2).and_raise(StandardError, 'ldap down')
      get '/api/v1/projects/1001/datasets', headers: bearer(token)
      expect(response).to have_http_status(:service_unavailable)
    end
  end

  # Project scope says WHICH projects; it never said whether the token may change
  # anything there. On a production instance that gap only stayed harmless because the
  # whole process ran read-only — moving the write policy to `additive` for the write-path
  # cutover would otherwise turn a read-only inspection credential into a job submitter.
  describe 'write authority (capabilities)' do
    it 'lets a read-only static token read but not submit' do
      token = ApiToken.issue(name: 'chain-ro', scope: [1001])[0]

      get '/api/v1/projects/1001/datasets', headers: bearer(token)
      expect(response).to have_http_status(:ok)

      post '/api/v1/jobs',
           params: { job: { dataset_id: ds1001.id, app_name: 'Fastqc' } },
           headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
      expect(body['error']).to eq('action not permitted for this token')
    end

    it 'rejects the write before authorization can even consider the payload' do
      token = ApiToken.issue(name: 'chain-ro', scope: [1001])[0]

      # out-of-scope project AND no write authority: the write gate answers first, so a
      # read-only token learns nothing about what it was denied.
      post '/api/v1/jobs',
           params: { job: { dataset_id: ds2002.id, app_name: 'Fastqc' } },
           headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
      expect(body['error']).to eq('action not permitted for this token')
    end

    it 'admits a static token that was granted write' do
      token = ApiToken.issue(name: 'chain-rw', scope: [1001], capabilities: %w[read write])[0]

      post '/api/v1/jobs',
           params: { job: { dataset_id: ds1001.id, app_name: 'Fastqc' } },
           headers: bearer(token)
      # Past the write gate: whatever happens next is submission logic, not authorization.
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'leaves safe methods untouched for a read-only token' do
      token = ApiToken.issue(name: 'chain-ro', scope: [1001])[0]
      get '/api/v1/jobs', headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end
  end
end
