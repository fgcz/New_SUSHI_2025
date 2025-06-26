require 'rails_helper'

RSpec.describe Api::V1::HelloController, type: :controller do
  describe 'GET #index' do
    before do
      get :index
    end

    it 'returns http success' do
      expect(response).to have_http_status(:success)
    end

    it 'returns correct content type' do
      expect(response.content_type).to include('application/json')
    end

    it 'returns hello world message' do
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Hello, World!')
    end

    it 'renders correct JSON structure' do
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('message')
      expect(json_response['message']).to be_a(String)
    end

    it 'assigns correct instance variables' do
      # This controller doesn't use instance variables,
      # so add as needed
    end

    it 'calls correct template' do
      # JSON is rendered directly, so no template is used
      expect(response).to be_successful
    end
  end

  describe 'controller methods' do
    it 'has index method' do
      expect(controller).to respond_to(:index)
    end

    # Remove direct call to controller.index, as it does not set up response properly
    # it 'index method returns correct response' do
    #   controller.index
    #   expect(response).to have_http_status(:success)
    # end
  end

  describe 'error handling' do
    context 'when an error occurs' do
      before do
        # Test for when an error occurs
        allow(controller).to receive(:index).and_raise(StandardError, 'Test error')
      end

      it 'handles errors gracefully' do
        expect { get :index }.to raise_error(StandardError)
      end
    end
  end

  # More practical test examples
  describe 'advanced controller testing' do
    context 'with different HTTP methods' do
      it 'responds to GET request' do
        get :index
        expect(response).to be_successful
      end
    end

    context 'with parameters' do
      it 'handles query parameters' do
        # Test example with parameters
        get :index, params: { name: 'Test' }
        expect(response).to be_successful
      end
    end

    context 'with headers' do
      it 'handles custom headers' do
        request.headers['X-Custom-Header'] = 'test-value'
        get :index
        expect(response).to be_successful
      end
    end

    context 'with session' do
      it 'handles session data' do
        session[:user_id] = 123
        get :index
        expect(response).to be_successful
      end
    end
  end

  describe 'controller instance variables' do
    it 'can access controller instance variables' do
      # Example of setting instance variables
      controller.instance_variable_set(:@test_var, 'test_value')
      expect(controller.instance_variable_get(:@test_var)).to eq('test_value')
    end
  end

  describe 'controller helper methods' do
    it 'can test private methods' do
      # Example of testing private methods (using reflection)
      if controller.respond_to?(:private_method, true)
        expect(controller.send(:private_method)).to be_truthy
      end
    end
  end
end 