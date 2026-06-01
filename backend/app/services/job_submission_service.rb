# Service for handling job submission
# Creates job scripts, registers datasets, and saves job records
class JobSubmissionService
  attr_reader :sushi_app, :input_dataset, :output_dataset, :job, :errors

  def initialize(dataset_id:, app_name:, parameters:, user:, next_dataset_name: nil, next_dataset_comment: nil)
    @dataset_id = dataset_id
    @app_name = app_name
    @parameters = parameters
    @user = user
    @next_dataset_name = next_dataset_name
    @next_dataset_comment = next_dataset_comment
    @errors = []
  end

  def submit
    # Validate inputs
    return false unless validate_inputs

    # Load and configure SushiApp
    return false unless load_sushi_app

    # Configure app with parameters
    configure_sushi_app

    # Generate job script
    script_path = generate_job_script
    return false unless script_path

    # Copy scratch files to gstore (input_dataset.tsv, parameters.tsv, scripts)
    # This must happen BEFORE job execution so the job can access these files
    return false unless copy_scratch_to_gstore

    # Create output dataset
    return false unless create_output_dataset

    # Save job record (with gstore script path)
    gstore_script_path = File.join(@sushi_app.gstore_script_dir, File.basename(script_path))
    return false unless create_job_record(gstore_script_path)

    true
  rescue StandardError => e
    @errors << "Unexpected error: #{e.message}"
    Rails.logger.error("Job submission error: #{e.message}\n#{e.backtrace.join("\n")}")
    false
  end

  private

  def validate_inputs
    @input_dataset = DataSet.find_by(id: @dataset_id)
    unless @input_dataset
      @errors << "Dataset not found: #{@dataset_id}"
      return false
    end

    # Check if app file exists
    # Normalize app_name: add "App" suffix if not present
    @normalized_app_name = @app_name.end_with?('App') ? @app_name : "#{@app_name}App"
    app_file = Rails.root.join('lib', 'apps', "#{@normalized_app_name}.rb")
    unless File.exist?(app_file)
      @errors << "Application not found: #{@app_name}"
      return false
    end

    true
  end

  def load_sushi_app
    # Require the app file (use normalized name with App suffix)
    app_file = Rails.root.join('lib', 'apps', "#{@normalized_app_name}.rb")
    require app_file

    # Instantiate the app (use normalized class name)
    @sushi_app = Object.const_get(@normalized_app_name).new
    true
  rescue NameError => e
    @errors << "Failed to load application class: #{@normalized_app_name} - #{e.message}"
    false
  rescue StandardError => e
    @errors << "Error loading application: #{e.message}"
    false
  end

  def configure_sushi_app
    # Set basic properties
    @sushi_app.dataset_sushi_id = @dataset_id
    @sushi_app.user = @user.login rescue @user.to_s
    @sushi_app.current_user = @user
    @sushi_app.project = "p#{@input_dataset.project.number}"
    @sushi_app.next_dataset_name = @next_dataset_name || "#{@sushi_app.name}_#{@dataset_id}"
    @sushi_app.next_dataset_comment = @next_dataset_comment

    # Prepare result directory FIRST (needed for input dataset TSV path)
    @sushi_app.prepare_result_dir

    # Load input dataset (creates TSV in result_dir for job nodes to access)
    @sushi_app.set_input_dataset

    # Set default parameters first
    @sushi_app.set_default_parameters

    # Override with user-provided parameters (normalize to plain Hash)
    normalized_params = normalize_parameters(@parameters)
    normalized_params.each do |key, value|
      @sushi_app.params[key] = value
    end
  end

  def generate_job_script
    # Generate script content
    script_content = @sushi_app.generate_job_script

    # Create script file
    timestamp = Time.now.strftime("%Y%m%d%H%M%S%L")
    script_filename = "#{@app_name}_#{@dataset_id}_#{timestamp}.sh"
    script_path = File.join(@sushi_app.job_script_dir, script_filename)

    # Ensure directory exists
    FileUtils.mkdir_p(@sushi_app.job_script_dir)

    # Write script
    File.write(script_path, script_content)
    FileUtils.chmod(0755, script_path)

    # Create parameters.tsv for job_manager
    # job_manager looks for parameters.tsv in parent of parent directory of script_path
    create_parameters_tsv(script_path)

    Rails.logger.info("Generated job script: #{script_path}")
    script_path
  rescue StandardError => e
    @errors << "Failed to generate job script: #{e.message}"
    nil
  end

  # Copy scratch directory to gstore before job submission
  # Uses g-req command for FGCZ environment (gstore is read-only)
  def copy_scratch_to_gstore
    src = @sushi_app.scratch_result_dir
    dest = @sushi_app.gstore_project_dir
    
    copy_cmd = SushiConfigHelper.copy_command(src, dest, now: true)
    Rails.logger.info("Copying scratch to gstore: #{copy_cmd}")
    
    success = system(copy_cmd)
    unless success
      @errors << "Failed to copy files from scratch to gstore: #{copy_cmd}"
      Rails.logger.error("Copy command failed: #{copy_cmd}")
      return false
    end
    
    # Wait for script file to appear in gstore (g-req may have NFS delay)
    wait_for_gstore_file(@sushi_app.gstore_script_dir, max_wait: 30)
    
    Rails.logger.info("Successfully copied scratch to gstore")
    true
  rescue StandardError => e
    @errors << "Error copying to gstore: #{e.message}"
    Rails.logger.error("Copy to gstore error: #{e.message}")
    false
  end
  
  # Wait for files to appear in gstore directory (handles NFS cache delay)
  def wait_for_gstore_file(gstore_dir, max_wait: 30)
    start_time = Time.now
    while (Time.now - start_time) < max_wait
      if Dir.exist?(gstore_dir) && Dir.glob(File.join(gstore_dir, '*.sh')).any?
        Rails.logger.info("Script file found in gstore after #{(Time.now - start_time).round(1)}s")
        return true
      end
      sleep 1
    end
    Rails.logger.warn("Waited #{max_wait}s but script file not yet visible in gstore")
    true # Continue anyway, file may appear soon
  end

  def create_parameters_tsv(script_path)
    # job_manager expects parameters.tsv at: dirname(dirname(script_path))/parameters.tsv
    # In scratch, this is scratch_result_dir/parameters.tsv
    parameters_file = File.join(@sushi_app.scratch_result_dir, 'parameters.tsv')
    
    # Write parameters as TSV
    CSV.open(parameters_file, 'w', col_sep: "\t") do |out|
      @sushi_app.params.each do |key, value|
        # Convert arrays to first value (user-selected value)
        actual_value = value.is_a?(Array) ? value.first : value
        out << [key, actual_value]
      end
      # Add additional required parameters
      out << ['dataRoot', @sushi_app.gstore_dir]
      out << ['resultDir', @sushi_app.result_dir]
      out << ['sushi_app', @normalized_app_name]
    end
    
    Rails.logger.info("Created parameters.tsv: #{parameters_file}")
  rescue StandardError => e
    Rails.logger.error("Failed to create parameters.tsv: #{e.message}")
    # Don't fail the job submission if parameters.tsv creation fails
  end

  def create_output_dataset
    # Get next dataset definition from app
    next_dataset_hash = @sushi_app.next_dataset

    # Prepare dataset array for save_dataset_to_database
    dataset_name = @sushi_app.next_dataset_name
    project_number = @input_dataset.project.number
    parent_id = @input_dataset.id
    comment = @sushi_app.next_dataset_comment || "Generated by #{@app_name}"

    data_set_arr = [
      'DataSetName', dataset_name,
      'ProjectNumber', project_number.to_s,
      'ParentID', parent_id.to_s,
      'Comment', comment
    ]

    # Convert next_dataset_hash to headers and rows
    headers = next_dataset_hash.keys
    rows = [next_dataset_hash.values]

    # Save to database
    @output_dataset_id = DataSet.save_dataset_to_database(
      data_set_arr: data_set_arr,
      headers: headers,
      rows: rows,
      user: @user,
      child: false,
      sushi_app_name: @app_name
    )

    @output_dataset = DataSet.find(@output_dataset_id)
    
    # Save parameters in the output dataset (normalize and skip validation)
    @output_dataset.job_parameters = normalize_parameters(@parameters)
    @output_dataset.save(validate: false)

    Rails.logger.info("Created output dataset: #{@output_dataset_id}")
    true
  rescue StandardError => e
    @errors << "Failed to create output dataset: #{e.message}"
    Rails.logger.error("Output dataset creation error: #{e.message}\n#{e.backtrace.join("\n")}")
    false
  end

  # Recursively convert ActionController::Parameters/HashWithIndifferentAccess
  # to plain Ruby Hash/Array with simple values for safe YAML serialization
  def normalize_parameters(value)
    if defined?(ActionController::Parameters) && value.is_a?(ActionController::Parameters)
      normalize_parameters(value.to_unsafe_h)
    elsif value.is_a?(Hash)
      value.to_h.each_with_object({}) do |(k, v), acc|
        acc[k.to_s] = normalize_parameters(v)
      end
    elsif value.is_a?(Array)
      value.map { |v| normalize_parameters(v) }
    else
      value
    end
  end

  def create_job_record(script_path)
    # Determine gstore path for script
    # In production, this would be copied to gstore, but for now we use the local path
    gstore_script_path = script_path

    @job = Job.new(
      script_path: gstore_script_path,
      next_dataset_id: @output_dataset_id,
      input_dataset_id: @input_dataset.id,
      status: 'CREATED',
      user: @sushi_app.user
    )

    if @job.save
      Rails.logger.info("Created job record: #{@job.id}")
      true
    else
      @errors << "Failed to save job: #{@job.errors.full_messages.join(', ')}"
      false
    end
  rescue StandardError => e
    @errors << "Failed to create job record: #{e.message}"
    false
  end
end

