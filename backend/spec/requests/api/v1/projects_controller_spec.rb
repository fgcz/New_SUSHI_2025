require 'rails_helper'

RSpec.describe 'Api::V1::Projects', type: :request do
  let(:user) { create(:user, login: 'testuser') }
  let!(:project1) { create(:project, number: 1001) }
  let!(:project2) { create(:project, number: 1002) }

  describe 'GET /api/v1/projects' do
    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns default project list and anonymous user' do
        get '/api/v1/projects'
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['projects']).to eq([{ 'number' => 1001 }])
        expect(body['current_user']).to eq('anonymous')
      end
    end

    context 'when JWT authentication is required' do
      before do
        mock_authentication_skipped(false)
      end

      it 'returns unauthorized without token' do
        get '/api/v1/projects'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns projects for authenticated user' do
        get '/api/v1/projects', headers: jwt_headers_for(user)
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['projects']).to eq([{ 'number' => 1001 }])
        expect(body['current_user']).to eq('testuser')
      end
    end
  end

  describe 'GET /api/v1/projects/:project_number/datasets' do
    let!(:dataset1) { create(:data_set, name: 'Dataset 1', project: project1, user: user) }
    let!(:dataset2) { create(:data_set, name: 'Dataset 2', project: project1, user: user) }
    let!(:dataset3) { create(:data_set, name: 'Another Dataset', project: project2, user: user) }

    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns datasets for accessible project' do
        get '/api/v1/projects/1001/datasets'
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['datasets'].size).to eq(2)
        expect(body['total_count']).to eq(2)
        expect(body['project_number']).to eq(1001)
        expect(body['page']).to eq(1)
        expect(body['per']).to eq(50)
      end

      it 'orders datasets by created_at desc' do
        # Create a newer dataset
        newer = create(:data_set, name: 'Newest', project: project1, user: user)
        get '/api/v1/projects/1001/datasets', params: { page: 1, per: 1 }
        body = JSON.parse(response.body)
        expect(body['datasets'].first['name']).to eq('Newest')
      end

      it 'returns forbidden for non-accessible project' do
        get '/api/v1/projects/9999/datasets'
        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Project not accessible')
      end
    end

    context 'when JWT authentication is required' do
      before { mock_authentication_skipped(false) }

      it 'returns unauthorized without token' do
        get '/api/v1/projects/1001/datasets'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns datasets for authenticated user with accessible project' do
        get '/api/v1/projects/1001/datasets', headers: jwt_headers_for(user)
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['datasets'].size).to eq(2)
        expect(body['datasets'].map { |d| d['name'] }).to match_array(['Dataset 1', 'Dataset 2'])
      end

      it 'returns forbidden for non-accessible project' do
        get '/api/v1/projects/9999/datasets', headers: jwt_headers_for(user)
        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Project not accessible')
      end
    end

    context 'with pagination' do
      before do
        mock_authentication_skipped(true)
        8.times { |i| create(:data_set, name: "Dataset #{i + 3}", project: project1, user: user) }
      end

      it 'respects page and per parameters' do
        get '/api/v1/projects/1001/datasets', params: { page: 1, per: 5 }
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['datasets'].size).to eq(5)
        expect(body['total_count']).to eq(10)
        expect(body['page']).to eq(1)
        expect(body['per']).to eq(5)
      end

      it 'returns second page correctly' do
        get '/api/v1/projects/1001/datasets', params: { page: 2, per: 5 }
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['datasets'].size).to eq(5)
        expect(body['page']).to eq(2)
      end

      it 'caps per at 200 and floors at 1' do
        get '/api/v1/projects/1001/datasets', params: { per: 500 }
        body = JSON.parse(response.body)
        expect(body['per']).to eq(200)

        get '/api/v1/projects/1001/datasets', params: { per: -5 }
        body = JSON.parse(response.body)
        expect(body['per']).to eq(1)
      end
    end

    context 'with search' do
      before { mock_authentication_skipped(true) }

      it 'filters by name' do
        get '/api/v1/projects/1001/datasets', params: { q: 'Dataset 1' }
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['datasets'].size).to eq(1)
        expect(body['datasets'].first['name']).to eq('Dataset 1')
      end

      it 'returns empty for non-matching search' do
        get '/api/v1/projects/1001/datasets', params: { q: 'NonExistent' }
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['datasets']).to eq([])
        expect(body['total_count']).to eq(0)
      end
    end

    context 'dataset serialization fields' do
      before do
        mock_authentication_skipped(true)
        dataset1.update!(sushi_app_name: 'TestApp', completed_samples: 5, bfabric_id: 12345)
      end

      it 'includes required fields' do
        get '/api/v1/projects/1001/datasets'
        body = JSON.parse(response.body)
        ds = body['datasets'].find { |d| d['name'] == 'Dataset 1' }
        expect(ds.keys).to include('id', 'name', 'sushi_app_name', 'completed_samples', 'samples_length', 'parent_id', 'children_ids', 'user_login', 'created_at', 'bfabric_id', 'project_number')
        expect(ds['user_login']).to eq(user.login)
        expect(ds['project_number']).to eq(1001)
      end

      it 'includes children_ids when child datasets exist' do
        child = create(:data_set, name: 'Child', project: project1, user: user, parent_id: dataset1.id)
        get '/api/v1/projects/1001/datasets'
        body = JSON.parse(response.body)
        ds = body['datasets'].find { |d| d['id'] == dataset1.id }
        expect(ds['children_ids']).to include(child.id)
      end
    end
  end

  describe 'GET /api/v1/projects/:project_number/jobs' do
    let!(:dataset1) { create(:data_set, name: 'Dataset1', project: project1, user: user) }
    let!(:dataset2) { create(:data_set, name: 'Dataset2', project: project1, user: user) }
    let!(:job1) { create(:job, data_set: dataset1, status: 'COMPLETED', user: 'alice', start_time: 1.day.ago) }
    let!(:job2) { create(:job, data_set: dataset1, status: 'FAILED', user: 'bob', start_time: 2.days.ago) }
    let!(:job3) { create(:job, data_set: dataset2, status: 'COMPLETED', user: 'alice', start_time: 3.days.ago) }

    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns paginated jobs for the project' do
        get '/api/v1/projects/1001/jobs?page=1&per=10'
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to be <= 10
        expect(body['total_count']).to eq(3)
        expect(body['page']).to eq(1)
        expect(body['per']).to eq(10)
        expect(body['project_number']).to eq(1001)
      end

      it 'orders jobs by created_at desc' do
        get '/api/v1/projects/1001/jobs'
        body = JSON.parse(response.body)
        job_ids = body['jobs'].map { |j| j['id'] }
        expect(job_ids.first).to eq(job3.id) # most recent
      end

      it 'filters by status' do
        get '/api/v1/projects/1001/jobs?status=COMPLETED'
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to eq(2)
        expect(body['jobs'].all? { |j| j['status'] == 'COMPLETED' }).to be true
        expect(body['filters']['status']).to eq('COMPLETED')
      end

      it 'filters by user' do
        get '/api/v1/projects/1001/jobs?user=alice'
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to eq(2)
        expect(body['jobs'].all? { |j| j['user'] == 'alice' }).to be true
        expect(body['filters']['user']).to eq('alice')
      end

      it 'filters by dataset_id' do
        get "/api/v1/projects/1001/jobs?dataset_id=#{dataset1.id}"
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to eq(2)
        expect(body['filters']['dataset_id']).to eq(dataset1.id)
      end

      it 'filters by date range' do
        from_date = 2.days.ago.to_date
        to_date = Date.today
        get "/api/v1/projects/1001/jobs?from_date=#{from_date}&to_date=#{to_date}"
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to be >= 1
        expect(body['filters']['from_date']).to eq(from_date.to_s)
        expect(body['filters']['to_date']).to eq(to_date.to_s)
      end

      it 'combines multiple filters' do
        get '/api/v1/projects/1001/jobs?status=COMPLETED&user=alice'
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to eq(2)
        expect(body['jobs'].all? { |j| j['status'] == 'COMPLETED' && j['user'] == 'alice' }).to be true
      end

      it 'returns empty array for project with no datasets' do
        # Create dataset to ensure project1 exists, then test with empty dataset scenario
        # Delete the jobs first
        Job.where(next_dataset_id: [dataset1.id, dataset2.id]).destroy_all
        DataSet.where(id: [dataset1.id, dataset2.id]).destroy_all
        
        get '/api/v1/projects/1001/jobs'
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['jobs']).to eq([])
        expect(body['total_count']).to eq(0)
      end

      it 'returns 403 for non-existent project (authorization checked first)' do
        get '/api/v1/projects/8888/jobs'
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for non-accessible project' do
        get '/api/v1/projects/7777/jobs'
        expect(response).to have_http_status(:forbidden)
      end

      it 'includes dataset information in job response' do
        get '/api/v1/projects/1001/jobs'
        body = JSON.parse(response.body)
        job = body['jobs'].first
        expect(job['dataset']).to be_present
        expect(job['dataset']['id']).to be_present
        expect(job['dataset']['name']).to be_present
      end

      it 'includes time information in ISO8601 format' do
        get '/api/v1/projects/1001/jobs'
        body = JSON.parse(response.body)
        job = body['jobs'].first
        expect(job['time']['start_time']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'when JWT authentication is required' do
      before { mock_authentication_skipped(false) }

      it 'returns unauthorized without token' do
        get '/api/v1/projects/1001/jobs'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns jobs for authenticated user' do
        get '/api/v1/projects/1001/jobs', headers: jwt_headers_for(user)
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['jobs']).to be_an(Array)
      end
    end

    context 'with pagination' do
      before do
        mock_authentication_skipped(true)
        # Create additional jobs
        8.times { |i| create(:job, data_set: dataset1, user: "user#{i}") }
      end

      it 'respects per parameter' do
        get '/api/v1/projects/1001/jobs?per=5'
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to eq(5)
        expect(body['total_count']).to eq(11) # 3 + 8
      end

      it 'returns second page correctly' do
        get '/api/v1/projects/1001/jobs?page=2&per=5'
        body = JSON.parse(response.body)
        expect(body['jobs'].size).to eq(5)
        expect(body['page']).to eq(2)
      end

      it 'caps per at 200' do
        get '/api/v1/projects/1001/jobs?per=500'
        body = JSON.parse(response.body)
        expect(body['per']).to eq(200)
      end
    end
  end
end


