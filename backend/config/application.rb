require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # Ignore lib directory entirely to avoid Zeitwerk naming conflicts
    config.autoload_lib(ignore: %w[assets tasks apps fgcz.rb global_variables.rb sushi_fabric.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    
    # Devise configuration
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore
    
    # SUSHI-specific configuration
    config.gstore_dir = ENV.fetch('GSTORE_DIR', '/srv/gstore')
    config.submit_job_script_dir = ENV.fetch('SUBMIT_JOB_SCRIPT_DIR', Rails.root.join('tmp', 'job_scripts').to_s)
    config.scratch_dir = ENV.fetch('SCRATCH_DIR', '/scratch')
  end
end
