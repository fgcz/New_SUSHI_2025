require 'rails_helper'

RSpec.describe 'Api::V1::Hello', type: :request do
  describe 'GET /api/v1/hello' do
    before do
      get '/api/v1/hello'
    end

    it 'returns success status' do
      expect(response).to have_http_status(:success)
    end

    it 'returns correct content type' do
      expect(response.content_type).to include('application/json')
    end

    it 'returns hello world message' do
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Hello, World!')
    end

    it 'returns valid JSON structure' do
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('message')
      expect(json_response['message']).to be_a(String)
    end
  end
end 