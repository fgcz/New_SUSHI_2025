# SushiFabric - SUSHI Application Framework
# Provides classes and methods to load and run SUSHI App classes
# Compatible with old SUSHI system

require_relative 'global_variables'

module SushiFabric
  class SushiApp
    include GlobalVariables
    
    attr_accessor :name, :analysis_category, :description, :required_columns, 
                  :required_params, :modules, :inherit_tags, :inherit_columns,
                  :dataset_sushi_id, :dataset, :dataset_hash, :project, :user,
                  :next_dataset_name, :next_dataset_comment, :current_user,
                  :result_dir, :gstore_dir, :scratch_dir, :job_script_dir,
                  :last_job, :input_dataset_tsv_path, :result_dataset,
                  :dataset_tsv_file, :parameterset_tsv_file,
                  :scratch_result_dir, :scratch_script_dir,
                  :gstore_result_dir, :gstore_script_dir, :gstore_project_dir,
                  :result_dir_base
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
      @gstore_dir = SushiConfigHelper.gstore_dir
      @scratch_dir = SushiConfigHelper.scratch_dir
      @job_script_dir = Rails.application.config.submit_job_script_dir
      @last_job = true
      @input_dataset_tsv_path = nil
      @result_dataset = []
    end
    
    # Set input dataset from database
    def set_input_dataset
      return unless @dataset_sushi_id
      
      dataset_record = DataSet.find_by_id(@dataset_sushi_id)
      return unless dataset_record
      
      @dataset_hash = dataset_record.samples.map { |sample| sample.to_hash }
      # For DATASET mode, @dataset is the full array; for SAMPLE mode it's a single hash
      if @params['process_mode'] == 'SAMPLE'
        @dataset = @dataset_hash.first if @dataset_hash.any?
      else
        @dataset = @dataset_hash
      end
      
      # Create input dataset TSV file for R apps
      prepare_input_dataset_tsv(dataset_record)
    end
    
    # Prepare input dataset TSV file in scratch directory
    # The job script will copy this to gstore using g-req
    def prepare_input_dataset_tsv(dataset)
      return unless dataset
      return unless @scratch_result_dir
      
      # Write input dataset TSV to scratch directory (local, writable)
      scratch_input_path = File.join(@scratch_result_dir, 'input_dataset.tsv')
      
      File.open(scratch_input_path, 'w') do |f|
        headers = dataset.headers
        f.puts headers.join("\t")
        dataset.samples.each do |sample|
          row = headers.map { |h| sample.to_hash[h] }
          f.puts row.join("\t")
        end
      end
      
      # The path that R scripts will use (on gstore, after copy)
      @input_dataset_tsv_path = File.join(@gstore_result_dir, 'input_dataset.tsv')
      
      Rails.logger.info("Created input dataset TSV in scratch: #{scratch_input_path}")
      Rails.logger.info("Target gstore path for R scripts: #{@input_dataset_tsv_path}")
    end
    
    # Set default parameters - subclasses can override
    def set_default_parameters
      # Set partition from config if not already set
      if @params['partition'].to_s.empty?
        @params['partition'] = SushiConfigHelper.default_partition
      end
    end
    
    # Check if dataset has a specific column
    def dataset_has_column?(column_name)
      return false unless @dataset_hash && @dataset_hash.any?
      @dataset_hash.first.keys.any? { |key| key.gsub(/\[.+\]/, '').strip == column_name }
    end
    
    # Generate job script content
    def generate_job_script
      script = []
      script << "#!/bin/bash"
      script << ""
      script << "set -eux"
      script << "set -o pipefail"
      script << "umask 0002"
      script << ""
      
      # Stage setup
      script << "#### SET THE STAGE"
      temp_dir_name = "#{@name.downcase}_#{Time.now.strftime('%Y-%m-%d--%H-%M-%S')}_temp$$"
      script << "SCRATCH_DIR=#{@scratch_dir}/#{temp_dir_name}"
      script << "GSTORE_DIR=#{@gstore_dir}"
      script << "INPUT_DATASET=#{@input_dataset_tsv_path}"
      script << "LAST_JOB=#{@last_job.to_s.upcase}"
      script << 'echo "Job runs on `hostname`"'
      script << 'echo "at $SCRATCH_DIR"'
      script << 'mkdir $SCRATCH_DIR || exit 1'
      script << 'cd $SCRATCH_DIR || exit 1'
      
      # Load modules
      if @modules && !@modules.empty?
        script << "source /usr/local/ngseq/etc/lmod_profile"
        module_versions = @modules.map { |m| find_module_version(m) }.join(' ')
        script << "module add #{module_versions}"
      end
      script << ""
      
      # Application commands
      script << "#### NOW THE ACTUAL JOBS STARTS"
      if respond_to?(:commands)
        script << commands
      else
        # Default: use run_RApp for R-based apps
        r_app_name = "EzApp#{@name.gsub(/App$/, '')}"
        script << run_RApp(r_app_name)
      end
      script << ""
      
      # Copy results to gstore and cleanup
      script << ""
      script << "#### JOB IS DONE WE PUT THINGS IN PLACE AND CLEAN UP"
      # Copy all result files to gstore (directory already exists from pre-submission copy)
      # Use individual file/subdir copy to avoid "destination exists" error
      script << "for f in *; do"
      script << "  if [ -e \"$f\" ]; then"
      script << "    #{SushiConfigHelper.copy_command('\"$f\"', @gstore_result_dir)}"
      script << "  fi"
      script << "done"
      script << "cd #{@scratch_dir}"
      script << "rm -rf #{temp_dir_name} || exit 1"
      script << ""
      
      script.join("\n")
    end
    
    # Find module version (look for latest available)
    def find_module_version(module_name)
      # For now, just return the module name as-is
      # In production, this would look up the actual available version
      module_name
    end
    
    # Prepare result directory paths (scratch and gstore)
    def prepare_result_dir
      return if @result_dir
      
      dataset = DataSet.find_by_id(@dataset_sushi_id) if @dataset_sushi_id
      next_dataset_name = @next_dataset_name || "#{@name}_result"
      timestamp = Time.now.strftime('%Y-%m-%d--%H-%M-%S')
      
      # Result directory base name
      @result_dir_base = if @next_dataset_name
                           "#{@next_dataset_name}_#{@dataset_sushi_id}_#{timestamp}"
                         else
                           "#{@name}_#{@dataset_sushi_id}_#{timestamp}"
                         end
      
      # Scratch directory (local, writable)
      @scratch_result_dir = File.join(SushiConfigHelper.scratch_dir, @result_dir_base)
      @scratch_script_dir = File.join(@scratch_result_dir, 'scripts')
      @job_script_dir = @scratch_script_dir  # Scripts are created in scratch
      
      # GStore directories (shared storage)
      if dataset && dataset.project
        @gstore_project_dir = File.join(@gstore_dir, "p#{dataset.project.number}")
        @result_dir = File.join(@gstore_project_dir, @result_dir_base)
      else
        @gstore_project_dir = File.join(@gstore_dir, 'results')
        @result_dir = File.join(@gstore_project_dir, @result_dir_base)
      end
      @gstore_result_dir = @result_dir
      @gstore_script_dir = File.join(@gstore_result_dir, 'scripts')
      
      # Create scratch directory (local, writable)
      FileUtils.mkdir_p(@scratch_result_dir)
      FileUtils.mkdir_p(@scratch_script_dir)
      
      Rails.logger.info("Prepared scratch directory: #{@scratch_result_dir}")
      Rails.logger.info("Target gstore directory: #{@gstore_result_dir}")
    end
    
    # Get next dataset definition - should be overridden in subclasses
    def next_dataset
      { 'Name' => @next_dataset_name || "#{@name}_result" }
    end
    
    # Get grandchild datasets - should be overridden in subclasses if needed
    def grandchild_datasets
      []
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
    
    def key?(key)
      @params.key?(key)
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
