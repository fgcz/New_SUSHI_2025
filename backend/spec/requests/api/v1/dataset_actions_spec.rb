require 'rails_helper'

# The dataset actions the UI offers next to a dataset: rename, comment, the
# gStore folder it lives in, the parameters that produced it, what a resubmit
# would re-run, and the dataset itself as TSV. Each replaces a frontend mock.
RSpec.describe 'Api::V1::Datasets actions', type: :request do
  before { mock_authentication_skipped(true) }

  let(:project) { create(:project, number: 1001) }
  let(:user) { create(:user) }
  let(:dataset) { create(:data_set, project: project, user: user, name: 'Original name') }

  describe 'PATCH /api/v1/datasets/:id' do
    it 'renames the dataset, which is one of legacy s two editable fields' do
      patch "/api/v1/datasets/#{dataset.id}", params: { dataset: { name: 'Renamed' } }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['name']).to eq('Renamed')
      expect(dataset.reload.name).to eq('Renamed')
    end

    it 'sets the comment' do
      patch "/api/v1/datasets/#{dataset.id}", params: { dataset: { comment: 'looks fine' } }

      expect(response).to have_http_status(:ok)
      expect(dataset.reload.comment).to eq('looks fine')
    end

    it 'ignores anything legacy does not let the page edit' do
      patch "/api/v1/datasets/#{dataset.id}",
            params: { dataset: { name: 'Renamed', sushi_app_name: 'Tampered', bfabric_id: 42 } }

      expect(response).to have_http_status(:ok)
      expect(dataset.reload.name).to eq('Renamed')
      expect(dataset.sushi_app_name).not_to eq('Tampered')
      expect(dataset.bfabric_id).to be_nil
    end

    it 'is 404 for an unknown dataset' do
      patch '/api/v1/datasets/999999', params: { dataset: { name: 'x' } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/datasets/:id/parameters' do
    it 'returns the resolved parameters of the job that produced it' do
      dataset.update!(job_parameters: { 'cores' => '1', 'ram' => 15, 'sushi_app' => 'FastqcApp' })

      get "/api/v1/datasets/#{dataset.id}/parameters"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['parameters'])
        .to eq('cores' => '1', 'ram' => 15, 'sushi_app' => 'FastqcApp')
    end

    it 'returns an empty hash for a dataset that no job produced' do
      get "/api/v1/datasets/#{dataset.id}/parameters"

      expect(JSON.parse(response.body)['parameters']).to eq({})
    end
  end

  describe 'GET /api/v1/datasets/:id/resubmit' do
    before do
      dataset.update!(sushi_app_name: 'FastqcApp',
                      job_parameters: { 'cores' => '1', 'sushi_app' => 'FastqcApp' })
    end

    it 'names the app to re-run and drops sushi_app, which is not one of its parameters' do
      get "/api/v1/datasets/#{dataset.id}/resubmit"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['app_name']).to eq('FastqcApp')
      expect(body['parameters']).to eq('cores' => '1')
    end
  end

  describe 'GET /api/v1/datasets/:id/paths' do
    it 'returns the project-relative gStore directories of the dataset files' do
      create(:sample, data_set: dataset,
                      key_value: "{'Name' => 'S1', 'Html [Link]' => 'p1001/Fastqc_run/S1.html'}")

      get "/api/v1/datasets/#{dataset.id}/paths"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['paths']).to eq(['p1001/Fastqc_run'])
    end
  end

  describe 'GET /api/v1/datasets/:id/tsv' do
    it 'serves the dataset as a tab-separated attachment' do
      create(:sample, data_set: dataset, key_value: "{'Name' => 'S1', 'Read1 [File]' => 'p1001/x/S1.fastq.gz'}")

      get "/api/v1/datasets/#{dataset.id}/tsv"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/tab-separated-values')
      expect(response.headers['Content-Disposition']).to include('Original name_dataset.tsv')
      expect(response.body.lines.first).to include("Name\t")
      expect(response.body).to include('S1')
    end
  end

  describe 'GET /api/v1/projects/:project_number/datasets/tsv' do
    it 'serves the project dataset LIST with legacy s eight columns' do
      dataset.update!(sushi_app_name: 'FastqcApp')

      get "/api/v1/projects/#{project.number}/datasets/tsv"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/tab-separated-values')
      expect(response.body.lines.first.strip.split("\t"))
        .to eq(%w[ID Name Project SushiApp Samples Who Created BFabricID])
      expect(response.body.lines[1]).to include('Original name', 'FastqcApp', '1001')
    end
  end
end
