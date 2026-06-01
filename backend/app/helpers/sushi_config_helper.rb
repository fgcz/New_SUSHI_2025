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
    
    # Get scratch directory path
    def scratch_dir
      storage_config['scratch_dir'] || '/scratch'
    end
    
    # Get gstore directory path
    def gstore_dir
      storage_config['gstore_dir'] || '/srv/gstore/projects'
    end
    
    # Get copy method (g-req or rsync)
    def copy_method
      storage_config['copy_method'] || 'g-req'
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

