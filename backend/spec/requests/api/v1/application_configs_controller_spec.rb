require 'rails_helper'

RSpec.describe 'Api::V1::ApplicationConfigs', type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { jwt_headers_for(user) }

  describe 'GET /api/v1/application_configs' do
    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns list of available applications' do
        get '/api/v1/application_configs'
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body).to have_key('applications')
        expect(body).to have_key('total_count')
        expect(body['applications']).to be_an(Array)
      end

      it 'includes Fastqc in the list' do
        get '/api/v1/application_configs'
        body = JSON.parse(response.body)
        app_names = body['applications'].map { |app| app['name'] }
        expect(app_names).to include('Fastqc')
      end
    end

    context 'with JWT authentication' do
      before { mock_authentication_skipped(false) }

      it 'returns list when authenticated' do
        get '/api/v1/application_configs', headers: auth_headers
        expect(response).to have_http_status(:success)
      end

      it 'returns 401 when not authenticated' do
        get '/api/v1/application_configs'
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/application_configs/:app_name' do
    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns Fastqc application configuration' do
        get '/api/v1/application_configs/Fastqc'
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        
        expect(body).to have_key('application')
        app = body['application']
        
        expect(app['name']).to eq('Fastqc')
        expect(app['class_name']).to eq('FastqcApp')
        expect(app['category']).to eq('QC')
        expect(app['description']).to be_a(String)
        expect(app['required_columns']).to include('Name', 'Read1')
        expect(app['required_params']).to include('paired', 'showNativeReports')
      end

      it 'returns form fields with correct structure' do
        get '/api/v1/application_configs/Fastqc'
        body = JSON.parse(response.body)
        app = body['application']
        
        expect(app['form_fields']).to be_an(Array)
        expect(app['form_fields'].size).to be > 0
        
        # Check for specific fields
        cores_field = app['form_fields'].find { |f| f['name'] == 'cores' }
        expect(cores_field).not_to be_nil
        expect(cores_field['type']).to eq('select')
        expect(cores_field['options']).to eq([8, 1, 2, 4, 8])
        expect(cores_field['default_value']).to eq(8)
        
        paired_field = app['form_fields'].find { |f| f['name'] == 'paired' }
        expect(paired_field).not_to be_nil
        expect(paired_field['type']).to eq('boolean')
        expect(paired_field['default_value']).to eq(false)
        
        special_options_field = app['form_fields'].find { |f| f['name'] == 'specialOptions' }
        expect(special_options_field).not_to be_nil
        expect(special_options_field['type']).to eq('text')
        expect(special_options_field['default_value']).to eq('')
      end

      it 'includes field descriptions' do
        get '/api/v1/application_configs/Fastqc'
        body = JSON.parse(response.body)
        app = body['application']
        
        ram_field = app['form_fields'].find { |f| f['name'] == 'ram' }
        expect(ram_field).not_to be_nil
        expect(ram_field['description']).to eq('GB')
      end

      it 'includes modules list' do
        get '/api/v1/application_configs/Fastqc'
        body = JSON.parse(response.body)
        app = body['application']
        
        expect(app['modules']).to be_an(Array)
        expect(app['modules']).to include('QC/FastQC')
      end

      it 'returns 404 for non-existent application' do
        get '/api/v1/application_configs/NonExistentApp'
        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Application not found')
      end

      it 'sanitizes app_name to prevent directory traversal' do
        get '/api/v1/application_configs/../../../etc/passwd'
        expect(response).to have_http_status(:not_found)
      end

      it 'is case-insensitive for app names' do
        get '/api/v1/application_configs/fastqc'
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['application']['name']).to eq('Fastqc')
      end
    end

    context 'with JWT authentication' do
      before { mock_authentication_skipped(false) }

      it 'returns config when authenticated' do
        get '/api/v1/application_configs/Fastqc', headers: auth_headers
        expect(response).to have_http_status(:success)
      end

      it 'returns 401 when not authenticated' do
        get '/api/v1/application_configs/Fastqc'
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

