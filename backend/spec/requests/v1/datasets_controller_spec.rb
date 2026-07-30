require 'rails_helper'

RSpec.describe 'V1::Datasets (bearer registration API)', type: :request do
  let(:tsv) { "Name\tRead1 [File]\ns1\tp1001/f1.fastq.gz\n" }

  def bearer(raw)
    { 'Authorization' => "Bearer #{raw}", 'CONTENT_TYPE' => 'application/json' }
  end

  describe 'authentication' do
    it 'returns 401 without a token' do
      post '/v1/datasets/validate',
           params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for an unknown token' do
      post '/v1/datasets/validate',
           params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
           headers: bearer('bogus')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for a machine-principal token (registration is not for the infra bridge)' do
      machine = ApiToken.issue(name: 'jm', principal: 'machine')[0]
      post '/v1/datasets/validate',
           params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
           headers: bearer(machine)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 400 for a malformed JSON body' do
      token = ApiToken.issue(name: 'reg', scope: [1001], capabilities: %w[read write])[0]
      post '/v1/datasets/validate', params: 'not-json', headers: bearer(token)
      expect(response).to have_http_status(:bad_request)
    end

    # The endpoint allowlist above restricts USER principals only; a static principal
    # passes it unconditionally. Write authority is what constrains a static service
    # credential, so registration now requires it explicitly.
    it 'returns 403 for a read-only token, whatever its project scope' do
      ro = ApiToken.issue(name: 'reg-ro', scope: [1001])[0]
      post '/v1/datasets/register',
           params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
           headers: bearer(ro)
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('action not permitted for this token')
    end
  end

  # Regression: with forgery protection enabled (as in dev/prod; RSpec defaults it
  # OFF), `protect_from_forgery with: :null_session` on this session-less bearer
  # controller 500s via Devise's handle_unverified_request → request.flash=.
  # skip_forgery_protection must fully remove the CSRF before_action.
  describe 'CSRF (forgery protection enabled, like dev/prod)' do
    around do |ex|
      prev = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      ex.run
    ensure
      ActionController::Base.allow_forgery_protection = prev
    end

    it 'does not 500 on a bearer POST (CSRF is skipped, not null-session-handled)' do
      token = ApiToken.issue(name: 'reg', scope: [1001], capabilities: %w[read write])[0]
      post '/v1/datasets/register',
           params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
           headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'static token' do
    let!(:token) { ApiToken.issue(name: 'reg', scope: [1001], capabilities: %w[read write])[0] }

    it 'validates a manifest for an in-scope project' do
      post '/v1/datasets/validate',
           params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
           headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['ok']).to be(true)
    end

    it 'registers a dataset for an in-scope project' do
      expect {
        post '/v1/datasets/register',
             params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
             headers: bearer(token)
      }.to change(DataSet, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['data_set_id']).to be_present
    end

    it 'returns 403 for an out-of-scope project' do
      post '/v1/datasets/register',
           params: { dataset_tsv: tsv, project_number: 9999, name: 'DS' }.to_json,
           headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
    end

    it 'set_bfabric_id is set-once (409 on a different value)' do
      ds = create(:data_set, project: create(:project, number: 1001), bfabric_id: 555)
      put "/v1/datasets/#{ds.id}/bfabric-id",
          params: { bfabric_id: 999 }.to_json, headers: bearer(token)
      expect(response).to have_http_status(:conflict)
    end

    it 'rejects a non-numeric bfabric_id with 422 (never coerces to 0)' do
      ds = create(:data_set, project: create(:project, number: 1001))
      put "/v1/datasets/#{ds.id}/bfabric-id",
          params: { bfabric_id: 'abc' }.to_json, headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(ds.reload.bfabric_id).to be_nil
    end

    it 'returns 422 for a blank dataset name (not a 500)' do
      post '/v1/datasets/register',
           params: { dataset_tsv: tsv, project_number: 1001, name: '' }.to_json,
           headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'user token' do
    let!(:token) { ApiToken.issue(name: 'u', principal: 'user', login: 'masaomi', ttl_days: 30,
                              capabilities: %w[read write])[0] }

    before { allow(FGCZ).to receive(:get_user_projects2).with('masaomi').and_return(['p1001']) }

    it 'forbids destroy (not on the user whitelist)' do
      ds = create(:data_set, project: create(:project, number: 1001))
      delete "/v1/datasets/#{ds.id}", headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 (no enumeration) for an out-of-scope dataset' do
      ds = create(:data_set, project: create(:project, number: 2002)) # not in user's projects
      put "/v1/datasets/#{ds.id}/bfabric-id",
          params: { bfabric_id: 5 }.to_json, headers: bearer(token)
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 503 when the membership resolver is unavailable' do
      allow(FGCZ).to receive(:get_user_projects2).and_raise(StandardError, 'ldap down')
      post '/v1/datasets/validate',
           params: { dataset_tsv: tsv, project_number: 1001, name: 'DS' }.to_json,
           headers: bearer(token)
      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
