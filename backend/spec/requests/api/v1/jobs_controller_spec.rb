require 'rails_helper'

RSpec.describe 'Api::V1::Jobs', type: :request do
  before do
    # Skip authentication for these tests
    mock_authentication_skipped(true)
  end

  describe 'POST /api/v1/jobs' do
    let(:project) { create(:project, number: 1001) }
    let(:user) { create(:user) }
    let(:dataset) { create(:data_set, project: project, user: user) }
    
    context 'with valid parameters' do
      let(:valid_params) do
        {
          job: {
            dataset_id: dataset.id,
            app_name: 'FastqcApp',
            parameters: {
              cores: 8,
              ram: 15,
              scratch: 100,
              paired: false,
              showNativeReports: false
            },
            next_dataset_name: 'FastQC_test_result',
            next_dataset_comment: 'Test job submission'
          }
        }
      end

      it 'creates a new job' do
        expect {
          post '/api/v1/jobs', params: valid_params, as: :json
        }.to change(Job, :count).by(1)
      end

      it 'creates an output dataset' do
        expect {
          post '/api/v1/jobs', params: valid_params, as: :json
        }.to change(DataSet, :count).by(1)
      end

      it 'returns created status' do
        post '/api/v1/jobs', params: valid_params, as: :json
        expect(response).to have_http_status(:created)
      end

      it 'returns job details' do
        post '/api/v1/jobs', params: valid_params, as: :json
        json = JSON.parse(response.body)
        
        expect(json['job']).to be_present
        expect(json['job']['status']).to eq('CREATED')
        expect(json['job']['input_dataset_id']).to eq(dataset.id)
        expect(json['output_dataset']).to be_present
        expect(json['output_dataset']['name']).to eq('FastQC_test_result')
      end

      it 'generates a job script file' do
        post '/api/v1/jobs', params: valid_params, as: :json
        json = JSON.parse(response.body)
        
        job = Job.find(json['job']['id'])
        expect(job.script_path).to be_present
        expect(File.exist?(job.script_path)).to be true
      end
    end

    context 'with invalid dataset_id' do
      let(:invalid_params) do
        {
          job: {
            dataset_id: 99999,
            app_name: 'FastqcApp',
            parameters: {}
          }
        }
      end

      it 'returns unprocessable entity status' do
        post '/api/v1/jobs', params: invalid_params, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error message' do
        post '/api/v1/jobs', params: invalid_params, as: :json
        json = JSON.parse(response.body)
        
        expect(json['errors']).to be_present
        expect(json['errors']).to include(match(/Dataset not found/))
      end
    end

    context 'with invalid app_name' do
      let(:invalid_params) do
        {
          job: {
            dataset_id: dataset.id,
            app_name: 'NonExistentApp',
            parameters: {}
          }
        }
      end

      it 'returns unprocessable entity status' do
        post '/api/v1/jobs', params: invalid_params, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error message' do
        post '/api/v1/jobs', params: invalid_params, as: :json
        json = JSON.parse(response.body)
        
        expect(json['errors']).to be_present
        expect(json['errors']).to include(match(/Application not found/))
      end
    end
  end

  describe 'GET /api/v1/jobs/:id' do
    let(:project) { create(:project, number: 1001) }
    let(:user) { create(:user) }
    let(:dataset) { create(:data_set, project: project, user: user) }
    let(:job) { create(:job, data_set: dataset, input_dataset_id: dataset.id) }

    it 'returns job details' do
      get "/api/v1/jobs/#{job.id}", as: :json
      expect(response).to have_http_status(:ok)
      
      json = JSON.parse(response.body)
      expect(json['job']['id']).to eq(job.id)
      expect(json['job']['status']).to eq(job.status)
    end

    it 'includes detailed information' do
      get "/api/v1/jobs/#{job.id}", as: :json
      json = JSON.parse(response.body)
      
      expect(json['job']['script_path']).to be_present
      expect(json['job']['submit_job_id']).to be_present
    end

    context 'with non-existent job' do
      it 'returns not found status' do
        get '/api/v1/jobs/99999', as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/jobs' do
    let(:project) { create(:project, number: 1001) }
    let(:user) { create(:user) }
    let(:dataset) { create(:data_set, project: project, user: user) }
    
    before do
      3.times { create(:job, data_set: dataset, input_dataset_id: dataset.id, user: 'testuser') }
      2.times { create(:job, data_set: dataset, input_dataset_id: dataset.id, user: 'otheruser', status: 'RUNNING') }
    end

    it 'returns all jobs' do
      get '/api/v1/jobs', as: :json
      expect(response).to have_http_status(:ok)
      
      json = JSON.parse(response.body)
      expect(json['jobs'].length).to eq(5)
      expect(json['total_count']).to eq(5)
    end

    it 'filters by user' do
      get '/api/v1/jobs', params: { user: 'testuser' }, as: :json
      json = JSON.parse(response.body)
      
      expect(json['jobs'].length).to eq(3)
      expect(json['total_count']).to eq(3)
    end

    it 'filters by status' do
      get '/api/v1/jobs', params: { status: 'RUNNING' }, as: :json
      json = JSON.parse(response.body)
      
      expect(json['jobs'].length).to eq(2)
      expect(json['total_count']).to eq(2)
    end

    it 'supports pagination' do
      get '/api/v1/jobs', params: { page: 1, per: 2 }, as: :json
      json = JSON.parse(response.body)
      
      expect(json['jobs'].length).to eq(2)
      expect(json['page']).to eq(1)
      expect(json['per']).to eq(2)
      expect(json['total_count']).to eq(5)
    end
  end
end

