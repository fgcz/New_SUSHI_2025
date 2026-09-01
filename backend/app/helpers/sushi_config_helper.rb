# Helper for SUSHI application configuration
# Manages partition settings and other deployment-specific configurations
module SushiConfigHelper
  class << self
    def config
      @config ||= load_config
    end
    
    # Get partition configuration
    def partition_config
      if Rails.env.production?
        # In production, check SUSHI_TYPE for deployment-specific settings
        sushi_type = ENV.fetch('SUSHI_TYPE', 'production')
        type_config = config.dig('production', 'types', sushi_type, 'partition')
        type_config || config.dig(Rails.env, 'partition') || default_partition_config
      else
        config.dig(Rails.env, 'partition') || default_partition_config
      end
    end
    
    # Get default partition
    def default_partition
      partition_config['default'] || 'employee'
    end
    
    # Get available partitions
    def available_partitions
      pc = partition_config
      
      # If dynamic is true and available is empty, fetch from SLURM
      if pc['dynamic'] && (pc['available'].nil? || pc['available'].empty?)
        fetch_slurm_partitions
      else
        pc['available'] || [default_partition]
      end
    end
    
    # Check if partitions should be fetched dynamically
    def dynamic_partitions?
      partition_config['dynamic'] == true
    end
    
    # Get storage configuration
    def storage_config
      if Rails.env.production?
        sushi_type = ENV.fetch('SUSHI_TYPE', 'production')
        type_config = config.dig('production', 'types', sushi_type, 'storage')
        type_config || config.dig(Rails.env, 'storage') || default_storage_config
      else
        config.dig(Rails.env, 'storage') || default_storage_config
      end
    end
    
    # Get scratch directory path (ENV takes precedence over sushi.yml)
    def scratch_dir
      ENV.fetch('SCRATCH_DIR', storage_config['scratch_dir'] || '/scratch')
    end

    # Get gstore directory path (ENV takes precedence over sushi.yml)
    def gstore_dir
      ENV.fetch('GSTORE_DIR', storage_config['gstore_dir'] || '/srv/gstore/projects')
    end

    # Where a RUNNING job's stdout/stderr live, as a LIST of directories.
    #
    # The job_manager daemon writes them into its own staging directory and they
    # reach the gStore result dir only when the job COMPLETES. There is more than
    # one such directory in practice, and it MOVED:
    #
    #   /misc/fgcz01/sushi/job_scripts          the daemon serving 082, measured
    #                                           2026-09-01 with a live RUNNING job
    #   /misc/fgcz01/sushi/.trxcopy/job_scripts the single value configured until
    #                                           now, measured on 083 on 2026-08-28
    #                                           and untouched since that day
    #
    # With one path configured, a running job's logs answered "Logs not found" on
    # the node that matters — the database recorded the right file and it was
    # world-readable; only our own allow-list rejected it. A list survives the next
    # move without another incident.
    #
    # Accepts a YAML list or a comma-separated string, in sushi.yml or in
    # JOB_LOG_DIRS. The older singular JOB_LOG_DIR / job_log_dir still works and
    # still means "exactly this one", so an operator can still narrow it.
    DEFAULT_JOB_LOG_DIRS = [
      '/misc/fgcz01/sushi/job_scripts',
      '/misc/fgcz01/sushi/.trxcopy/job_scripts'
    ].freeze

    def job_log_dirs
      raw = ENV['JOB_LOG_DIRS'] || ENV['JOB_LOG_DIR'] ||
            storage_config['job_log_dirs'] || storage_config['job_log_dir']

      list = Array(raw).flat_map { |entry| entry.to_s.split(',') }.map(&:strip).reject(&:empty?)
      list.empty? ? DEFAULT_JOB_LOG_DIRS : list
    end

    # Get copy method (ENV takes precedence over sushi.yml)
    def copy_method
      ENV.fetch('SUSHI_COPY_METHOD', storage_config['copy_method'] || 'g-req')
    end

    # Should the submit-time scratch->gstore copy use the `copynow` fast path?
    #
    # `copynow` is a trxcopy-ONLY path: gtools runs `ssh trxcopy@<file server>` for both the
    # mkdir and the rsync (gstore-request: copynow(..., ssh_user, ssh_key)). Legacy production
    # SUSHI can use it because Passenger runs it AS trxcopy. New SUSHI runs as masaomi, whose
    # only key authorised for trxcopy is passphrase-protected and not a default identity name,
    # so ssh can offer it only through an ssh-agent. Where no agent is inherited the ssh falls
    # back to a password prompt with its output discarded and blocks forever.
    #
    # The queued `g-req -w copy` needs no ssh at all — it registers a request for the transfer
    # daemon (which is already trxcopy) and waits for it. That is the same path the generated
    # job script's footer has always used from SLURM compute nodes as masaomi.
    #
    # Default OFF, so an agentless deployment works. Set SUSHI_SUBMIT_COPY_NOW=1 on an instance
    # that really runs as trxcopy to take the fast path again.
    def submit_copy_now?
      %w[1 true yes].include?(ENV.fetch('SUSHI_SUBMIT_COPY_NOW', '').downcase)
    end

    # Wall-clock bound for the submit-time gstore copy, in seconds.
    #
    # gtools' own wait() is `while True` with no timeout, so an unfulfilled request or a stalled
    # ssh holds the calling thread indefinitely. Bound it here instead.
    def gstore_copy_timeout
      ENV.fetch('SUSHI_GSTORE_COPY_TIMEOUT', '900').to_i
    end

    # Generate copy command based on environment
    def copy_command(src, dest, options = {})
      case copy_method
      when 'g-req'
        if options[:force]
          "g-req copynow -f #{src} #{dest}"
        elsif options[:now]
          "g-req copynow #{src} #{dest}"
        elsif options[:queue] == 'heavy'
          "g-req -w copy -f heavy #{src} #{dest}"
        else
          "g-req -w copy #{src} #{dest}"
        end
      else
        # rsync for demo/local environments
        "rsync -r #{src} #{dest}/"
      end
    end
    
    private
    
    def default_storage_config
      {
        'scratch_dir' => '/scratch',
        'gstore_dir' => '/srv/gstore/projects',
        'copy_method' => 'g-req'
      }
    end
    
    def load_config
      config_path = Rails.root.join('config', 'sushi.yml')
      if File.exist?(config_path)
        yaml_content = File.read(config_path)
        erb_content = ERB.new(yaml_content).result
        YAML.load(erb_content, aliases: true)
      else
        {}
      end
    rescue => e
      Rails.logger.error("Error loading sushi.yml: #{e.message}")
      {}
    end
    
    def default_partition_config
      {
        'default' => 'employee',
        'available' => [],
        'dynamic' => true
      }
    end
    
    def fetch_slurm_partitions
      command = "sinfo --format=%R 2>/dev/null"
      list = `#{command}`.split(/\n/)
      list.delete("PARTITION")
      
      # Move default partition to first position if it exists
      default = default_partition
      if list.include?(default)
        list.delete(default)
        list.unshift(default)
      end
      
      list.empty? ? [default] : list
    rescue => e
      Rails.logger.warn("Failed to get SLURM partitions: #{e.message}")
      [default_partition]
    end
  end
end

