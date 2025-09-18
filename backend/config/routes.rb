Rails.application.routes.draw do
  if defined?(Rswag::Ui::Engine) && defined?(Rswag::Api::Engine)
    mount Rswag::Ui::Engine => '/api-docs'
    mount Rswag::Api::Engine => '/api-docs'
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise routes (conditional based on authentication config)
  devise_config = {}
  if defined?(AuthenticationHelper) && AuthenticationHelper.oauth2_login_enabled?
    devise_config[:omniauth_callbacks] = 'authentication#oauth_callback'
  end
  
  devise_for :users, controllers: devise_config

  # Authentication routes
  get 'auth/:provider/callback', to: 'authentication#oauth_callback'
  get 'auth/failure', to: 'authentication#oauth_failure'
  get 'auth/login_options', to: 'authentication#login_options'
  post 'auth/setup_two_factor', to: 'authentication#setup_two_factor'
  post 'auth/enable_two_factor', to: 'authentication#enable_two_factor'
  post 'auth/wallet_auth', to: 'authentication#wallet_auth'

  # Defines the root path route ("/")
  root "home#index"

  namespace :api do
    namespace :v1 do
      # Public API routes (no JWT authentication required)
      get 'hello', to: 'hello#index'
      
      # JWT Authentication routes (public - no authentication required)
      post 'auth/login', to: 'auth#login'
      post 'auth/register', to: 'auth#register'
      post 'auth/logout', to: 'auth#logout'
      get 'auth/verify', to: 'auth#verify'
      
      # Private API routes (JWT authentication required)
      # These endpoints require a valid JWT token in the Authorization header
      resources :authentication_config, only: [:index, :update]
      resources :datasets, only: [:index, :show, :create]

      # Projects and nested datasets listing
      resources :projects, only: [:index], param: :project_number do
        get 'datasets', to: 'projects#datasets'
        get 'datasets/tree', to: 'projects#datasets_tree'
      end
      
      # Private test endpoints (JWT authentication required)
      get 'test/protected', to: 'test#protected'
      get 'test/user_info', to: 'test#user_info'
    end
  end
end
