# frozen_string_literal: true

require 'rails_helper'

# The write-capability gate for sessions minted from a B-Fabric token.
#
# Until now the JWT path had NO write-capability check of any kind: ApiToken#can_write?
# guards the ApiToken bearer surface only, so the moment the Rack policy permitted a POST,
# every signed-in user could submit and the employee gate was the only narrowing.
#
# An anonymous controller is used deliberately. The gate lives in Api::V1::BaseController
# and applies to every route beneath it; testing it through one concrete endpoint would
# tangle the assertion with that endpoint's own fixtures and prove less.
RSpec.describe Api::V1::BaseController, type: :controller do
  controller(Api::V1::BaseController) do
    def index = render(json: { ok: true })
    def create = render(json: { ok: true })
    def destroy = render(json: { ok: true })
  end

  before do
    # An anonymous controller subclassing a NAMESPACED one keeps the parent's
    # controller_path, so the routes must name `api/v1/base`, not `anonymous`.
    routes.draw do
      get 'index' => 'api/v1/base#index'
      post 'create' => 'api/v1/base#create'
      delete 'destroy/:id' => 'api/v1/base#destroy'
    end
  end

  let(:user) { User.create!(login: 'masaomi', email: 'masaomi@example.com', password: 'password123') }

  def authenticate_as(**extra_claims)
    request.headers['Authorization'] = "Bearer #{generate_jwt_token(user, extra_claims)}"
  end

  describe 'a session minted from a B-Fabric token' do
    it 'may READ regardless of the scopes B-Fabric granted' do
      authenticate_as(src: 'bfabric', scope: 'openid api:read')
      get :index
      expect(response).to have_http_status(:ok)
    end

    it 'may NOT write when B-Fabric did not grant api:write' do
      authenticate_as(src: 'bfabric', scope: 'openid api:read')
      post :create
      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('insufficient_scope')
      expect(body['message']).to include('api:write')
    end

    it 'may write when B-Fabric did grant api:write' do
      authenticate_as(src: 'bfabric', scope: 'openid api:read api:write')
      post :create
      expect(response).to have_http_status(:ok)
    end

    it 'is refused on every non-safe verb, not only POST' do
      authenticate_as(src: 'bfabric', scope: 'api:read')
      delete :destroy, params: { id: 1 }
      expect(response).to have_http_status(:forbidden)
    end

    it 'is refused when the scope claim is missing entirely' do
      authenticate_as(src: 'bfabric')
      post :create
      expect(response).to have_http_status(:forbidden)
    end

    # A scope check that matched substrings would let `api:write_nothing` through, and
    # `api:read` would satisfy a naive `include?` on the raw string.
    it 'matches whole scopes, not substrings' do
      authenticate_as(src: 'bfabric', scope: 'api:read api:writes-not-really')
      post :create
      expect(response).to have_http_status(:forbidden)
    end
  end

  # The gate is ADDITIVE. An LDAP session carries no `src` claim and must behave exactly
  # as it did before this existed — otherwise this "narrowing" is a regression for every
  # human user of the system.
  describe 'a session minted by the password login' do
    it 'is completely unaffected and may still write' do
      authenticate_as
      post :create
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'an unauthenticated request' do
    it 'is refused by the existing authentication layer, not by this gate' do
      post :create
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
