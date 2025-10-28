# Minimal SushiFabric stub for parsing SUSHI App files
# This stub provides the minimum necessary classes and methods
# to load and instantiate SUSHI App classes without requiring
# the full sushi_fabric gem infrastructure

module SushiFabric
  class SushiApp
    attr_accessor :name, :analysis_category, :description, :required_columns, 
                  :required_params, :modules, :inherit_tags, :inherit_columns,
                  :dataset_sushi_id, :dataset, :dataset_hash, :project, :user,
                  :next_dataset_name, :next_dataset_comment, :current_user,
                  :result_dir, :gstore_dir, :scratch_dir, :job_script_dir
    attr_reader :params
    
    def initialize
      @name = ''
      @analysis_category = ''
      @description = ''
      @required_columns = []
      @required_params = []
      @params = SushiParams.new
      @modules = []
      @inherit_tags = []
      @inherit_columns = []
      @dataset_sushi_id = nil
      @dataset = nil
      @dataset_hash = []
      @project = nil
      @user = nil
      @next_dataset_name = nil
      @next_dataset_comment = nil
      @current_user = nil
      @result_dir = nil
      @gstore_dir = Rails.application.config.gstore_dir
      @scratch_dir = Rails.application.config.scratch_dir
      @job_script_dir = Rails.application.config.submit_job_script_dir
    end
    
    # Set input dataset from database
    def set_input_dataset
      return unless @dataset_sushi_id
      
      dataset = DataSet.find_by_id(@dataset_sushi_id)
      return unless dataset
      
      @dataset_hash = dataset.samples.map { |sample| sample.to_hash }
      @dataset = @dataset_hash.first if @dataset_hash.any?
    end
    
    # Set default parameters - subclasses can override
    def set_default_parameters
      # Default implementation - can be overridden in subclasses
    end
    
    # Check if dataset has a specific column
    def dataset_has_column?(column_name)
      return false unless @dataset_hash && @dataset_hash.any?
      @dataset_hash.first.keys.any? { |key| key.gsub(/\[.+\]/, '').strip == column_name }
    end
    
    # Extract columns from dataset
    def extract_columns(options = {})
      return {} unless @dataset_hash && @dataset_hash.any?
      
      if colnames = options[:colnames]
        result = {}
        colnames.each do |colname|
          @dataset_hash.first.each do |key, value|
            if key.gsub(/\[.+\]/, '').strip == colname
              result[key] = value
            end
          end
        end
        result
      else
        {}
      end
    end
    
    # Generate job script content
    def generate_job_script
      script = []
      script << "#!/bin/bash"
      script << "set -e"
      script << "set -o pipefail"
      script << ""
      script << "# Job: #{@name}"
      script << "# Dataset: #{@dataset_sushi_id}"
      script << "# User: #{@user}"
      script << "# Project: #{@project}"
      script << ""
      
      # Load modules if specified
      if @modules && !@modules.empty?
        script << "# Load modules"
        @modules.each do |mod|
          script << "module load #{mod}"
        end
        script << ""
      end
      
      # Set directories
      script << "# Directories"
      script << "GSTORE_DIR=#{@gstore_dir}"
      script << "RESULT_DIR=#{@result_dir}"
      script << "SCRATCH_DIR=#{@scratch_dir}"
      script << ""
      
      # Application-specific commands
      script << "# Application commands"
      if respond_to?(:commands)
        script << commands
      else
        script << "echo 'No commands defined'"
      end
      
      script << ""
      script << "echo 'Job completed'"
      
      script.join("\n")
    end
    
    # Stub methods that apps may call
    def run_RApp(app_name)
      "R --vanilla --slave << EOT\nEOT"
    end
    
    def run_PyApp(app_name, options = {})
      "python3 << EOT\nEOT"
    end
    
    # Prepare result directory path
    def prepare_result_dir
      return if @result_dir
      
      dataset = DataSet.find_by_id(@dataset_sushi_id) if @dataset_sushi_id
      next_dataset_name = @next_dataset_name || "#{@name}_result"
      
      if dataset && dataset.project
        project_dir = File.join(@gstore_dir, 'projects', "p#{dataset.project.number}")
        @result_dir = File.join(project_dir, next_dataset_name)
      else
        @result_dir = File.join(@gstore_dir, 'results', next_dataset_name)
      end
    end
    
    # Get next dataset definition
    def next_dataset
      # Default implementation - should be overridden in subclasses
      { 'Name' => @next_dataset_name || "#{@name}_result" }
    end
  end
  
  # SushiParams behaves like a Hash but also tracks metadata
  class SushiParams
    def initialize
      @params = {}
      @metadata = {}
    end
    
    def []=(*args)
      if args.size == 3
        # Handle metadata like @params['ram', 'description'] = "GB"
        # This comes in as ['ram', 'description', 'GB']
        param_name, meta_key, value = args
        @metadata[param_name] ||= {}
        @metadata[param_name][meta_key] = value
      elsif args.size == 2
        # Handle regular param like @params['ram'] = 15
        key, value = args
        @params[key] = value
      else
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)"
      end
    end
    
    def [](key)
      @params[key]
    end
    
    def each(&block)
      @params.each(&block)
    end
    
    def keys
      @params.keys
    end
    
    def to_h
      @params.dup
    end
    
    def metadata_for(key)
      @metadata[key] || {}
    end
    
    def all_metadata
      @metadata
    end
  end
end

