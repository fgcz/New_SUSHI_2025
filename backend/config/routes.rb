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

  # Machine-callable, bearer-only registration API (ApiToken). Top-level /v1 so
  # btools reaches New SUSHI by base-URL swap (mirrors legacy production SUSHI).
  # Bearer-only ActionController::Base — not under the JWT /api/v1 surface.
  namespace :v1 do
    post   'datasets/validate',      to: 'datasets#validate'
    post   'datasets/register',      to: 'datasets#register'
    put    'datasets/:id/bfabric-id', to: 'datasets#set_bfabric_id'
    delete 'datasets/:id',           to: 'datasets#destroy'
  end

  # Machine-to-machine internal bridge (bearer-only, static ApiToken). Mirrors
  # Ronald's FastAPI /internal/legacy/* so job_manager / GeoUploader reach New
  # SUSHI by base-URL swap. See app/controllers/internal/legacy_controller.rb.
  # by-bfabric is declared before the :dataset_id routes so it is not shadowed.
  namespace :internal do
    scope :legacy do
      get   'jobs',                              to: 'legacy#jobs'
      patch 'jobs/:id',                          to: 'legacy#patch_job'
      get   'datasets/:dataset_id/jobs',         to: 'legacy#dataset_jobs'
      get   'projects/:project_number/datasets', to: 'legacy#project_datasets'
      get   'datasets/by-bfabric/:bfabric_id',   to: 'legacy#dataset_by_bfabric'
      get   'datasets/:dataset_id/parent',       to: 'legacy#dataset_parent'
      get   'datasets/:dataset_id/project',      to: 'legacy#dataset_project'
      get   'datasets/:dataset_id/samples',      to: 'legacy#dataset_samples'
      post  'datasets/:dataset_id/update-completed-samples', to: 'legacy#update_completed_samples'
    end
  end

  namespace :api do
    namespace :v1 do
      # Public API routes (no JWT authentication required)
      get 'hello', to: 'hello#index'
      
      # JWT Authentication gateway (B2). Public/cookie endpoints self-skip bearer auth
      # via JwtAuthenticatable#skip_jwt_authentication?; me/logout-all require a bearer token.
      get  'auth/login_options', to: 'auth#login_options' # public
      post 'auth/login', to: 'auth#login'                 # public
      post 'auth/register', to: 'auth#register'           # public
      post 'auth/refresh', to: 'auth#refresh'             # refresh cookie
      post 'auth/logout', to: 'auth#logout'               # refresh cookie
      post 'auth/logout-all', to: 'auth#logout_all'       # bearer
      get  'auth/me', to: 'auth#me'                        # bearer
      get  'auth/verify', to: 'auth#verify'               # DEPRECATED (use auth/me)

      # B-Fabric OIDC session exchange. A GET on purpose (the Rack write guard never sees
      # safe methods, so NO_WRITE_PATHS does not grow), and namespaced under /api/v1
      # MANDATORILY: the top-level `get 'auth/:provider/callback'` declared near the top of
      # this file would otherwise swallow /auth/bfabric/callback into
      # AuthenticationController#oauth_callback, which calls User.from_omniauth and blows
      # up on the production schema (no provider/uid columns).
      get 'auth/bfabric/session', to: 'bfabric_auth#session'
      # The browser login. GETs for the same reason: the Rack guard never sees a safe
      # method, so NO_WRITE_PATHS stays at its two entries.
      get 'auth/bfabric/device/start', to: 'bfabric_auth#device_start'
      get 'auth/bfabric/device/poll',  to: 'bfabric_auth#device_poll'

      # Private API routes (JWT authentication required)
      # These endpoints require a valid JWT token in the Authorization header
      resources :authentication_config, only: [:index, :update]
      resources :datasets, only: [:index, :show, :create, :update] do
        collection do
          post 'from_tsv'
        end
        member do
          get 'tree'
          get 'runnable_apps'
          get 'samples'
          get 'paths'
          get 'parameters'
          get 'resubmit'
          get 'tsv'
        end
      end

      # Projects and nested datasets listing
      resources :projects, only: [:index], param: :project_number do
        get 'datasets', to: 'projects#datasets'
        get 'datasets/tree', to: 'projects#datasets_tree'
        get 'datasets/tsv', to: 'projects#datasets_tsv'
        member do
          get 'jobs'
        end
      end
      
      # Read-only gStore browser
      resources :files, only: [:index]

      # Job counts per submitter
      resources :rankings, only: [:index]

      # Application configurations
      resources :application_configs, only: [:index, :show], param: :app_name
      
      # Job submission and management
      resources :jobs, only: [:create, :show, :index] do
        member do
          get 'script'
          get 'logs'
        end
      end
      
      # Private test endpoints (JWT authentication required)
      get 'test/protected', to: 'test#protected'
      get 'test/user_info', to: 'test#user_info'
    end
  end
end
