require_relative "boot"

require "rails/all"
require_relative "../lib/middleware/sushi_read_only_guard"
require_relative "../lib/env_api_token"

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
    # env_api_token.rb is required above rather than autoloaded ON PURPOSE: the
    # development reloader discards autoloaded constants between requests, which
    # would re-read ENV and undo the once-per-process freeze of the credential —
    # and the production node runs in development mode. See lib/env_api_token.rb.
    config.autoload_lib(ignore: %w[assets tasks apps middleware fgcz.rb global_variables.rb sushi_fabric.rb
                                   env_api_token.rb])

    # Server-side write-policy guard (SUSHI_WRITE_POLICY = read_only | additive | full;
    # SUSHI_READ_ONLY=1 still means read_only; default full). Rack-level so it covers
    # every controller hierarchy uniformly. See lib/middleware/sushi_read_only_guard.rb.
    config.middleware.use Middleware::SushiReadOnlyGuard

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
    # lmod profile sourced by generated job scripts, and used to resolve each requested
    # module to its concrete default version (see SushiApp#resolve_module_versions).
    # Empty disables both the `source` line and version resolution.
    config.module_source = ENV.fetch('MODULE_SOURCE', '/usr/local/ngseq/etc/lmod_profile')

    # Generic legacy-app loader (see LegacyAppLoader): directory holding legacy SUSHI
    # *App.rb files (e.g. a legacy SUSHI checkout's master/lib). Empty = feature off
    # (only backend-native ported apps in lib/apps are exposed).
    config.legacy_apps_dir = ENV.fetch('LEGACY_APPS_DIR', '')
    # Allow-list of legacy app base names verified to run headless on the backend shim.
    # Only these legacy apps are exposed via the API; grows as apps are verified.
    # Verified to load & generate job scripts headless on the backend shim (Level-1).
    # DATASET: FastqScreen, DESeq2, EdgeR, CountQC, Fastqc10x, FastqScreen10x,
    #          RnaBamStats, Mpileup. SAMPLE fan-out: STAR, FeatureCounts, CellRangerMulti,
    #          Kallisto, Bowtie2, BWA, ScSeurat, DnaBamStats.
    config.legacy_apps_allowlist =
      ENV.fetch('LEGACY_APPS_ALLOWLIST',
                'FastqScreen,DESeq2,EdgeR,CountQC,Fastqc10x,FastqScreen10x,RnaBamStats,Mpileup,' \
                'STAR,FeatureCounts,CellRangerMulti,Kallisto,Bowtie2,BWA,ScSeurat,DnaBamStats')
         .split(',').map(&:strip).reject(&:empty?)
  end
end
