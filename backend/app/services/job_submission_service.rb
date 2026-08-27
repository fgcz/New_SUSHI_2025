require 'open3'

# Service for handling job submission
# Creates job scripts, registers datasets, and saves job records
class JobSubmissionService
  # `timeout` reports 124 when it had to stop the command itself.
  TIMEOUT_EXIT_STATUS = 124

  attr_reader :sushi_app, :input_dataset, :output_dataset, :job, :jobs, :errors

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

    # Legacy runs the app's own preprocess hook here — after the input dataset, result dir
    # and parameters are settled, before validation and before any script is generated
    # (SushiApp#run -> #test_run: set_input_dataset, set_dir_paths, preprocess, ...).
    # It is where an app seeds @random_string for its Live Report link, adds 'Read2' to
    # @required_columns for a paired run, and appends to @required_params — so it must run
    # BEFORE resolve_and_validate_params, not after.
    @sushi_app.preprocess

    # Legacy's other pre-flight gate, and it must run AFTER preprocess for the same reason
    # the params gate does: preprocess is where an app appends to @required_columns (FastqcApp
    # adds 'Read2' for a paired run).
    return false unless validate_required_columns

    # Resolve raw form-shaped defaults and enforce required params BEFORE anything with a
    # side effect (job scripts, gstore copy, DB rows). See the method comment.
    return false unless resolve_and_validate_params

    # Build job units: one per sample in SAMPLE mode (legacy fan-out), one for the
    # whole dataset in DATASET/BATCH mode. Each unit is a written job script plus the
    # next_dataset row it produces.
    @job_units = build_job_units
    return false if @job_units.nil? || @job_units.empty?

    # Shared parameters.tsv for the job_manager (@params are identical across samples)
    create_parameters_tsv

    # dataset.tsv describing the output the run will produce, alongside input_dataset.tsv
    # and parameters.tsv — legacy writes all three into the result directory and users
    # and downstream tooling read it from there.
    create_next_dataset_tsv(@job_units.map { |u| u[:next_dataset] })

    # grandchild_dataset.tsv, written next to the other three so it is picked up by the same
    # copy below. Must come after build_job_units: the app derives its grandchild rows from the
    # samples it actually processed.
    @grandchild_tsv = @sushi_app.write_grandchild_dataset_tsv

    # Copy scratch files to gstore (input_dataset.tsv, parameters.tsv, scripts)
    # This must happen BEFORE job execution so the job can access these files
    return false unless copy_scratch_to_gstore

    # Create ONE output dataset holding every unit's next_dataset row
    return false unless create_output_dataset(@job_units.map { |u| u[:next_dataset] })

    # And the grandchild dataset, if the app declared one — a child of the output dataset, so
    # it needs the output dataset's id.
    create_grandchild_datasets

    # Save one job record per unit (all pointing at the shared output dataset)
    return false unless create_job_records(@job_units)

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

    # Check the app is resolvable (native ported app or allow-listed legacy app)
    @normalized_app_name = LegacyAppLoader.normalize(@app_name)
    unless LegacyAppLoader.available?(@app_name)
      @errors << "Application not found: #{@app_name}"
      return false
    end

    true
  end

  def load_sushi_app
    # Load & instantiate via the shared loader (native app or legacy-on-shim)
    app_class = LegacyAppLoader.load(@app_name)
    unless app_class
      @errors << "Failed to load application class: #{@normalized_app_name}"
      return false
    end

    @sushi_app = app_class.new
    true
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
    # Before the name is used: prepare_result_dir applies legacy's @name.gsub!(/\s/,'_')
    # (sushiApp.rb:507), but the default output-dataset name is derived HERE, one line
    # earlier, and it becomes the gStore result directory. Without this, an API submission
    # that omits next_dataset_name would name the result dir "samtools mpileup_810_<ts>" —
    # a path with a space, which g-req cannot transfer.
    @sushi_app.normalize_name!
    @sushi_app.next_dataset_name = @next_dataset_name || "#{@sushi_app.name}_#{@dataset_id}"
    @sushi_app.next_dataset_comment = @next_dataset_comment

    # Prepare result directory FIRST (needed for input dataset TSV path)
    @sushi_app.prepare_result_dir

    # Load input dataset (creates TSV in result_dir for job nodes to access)
    @sushi_app.set_input_dataset

    # Set default parameters first
    @sushi_app.set_default_parameters

    # Centralized base defaults: some (legacy) apps override set_default_parameters
    # WITHOUT calling super, so the shim's base defaults never run — leaving partition
    # empty (the "-p nan" class of bug). Apply the base partition default here so it
    # holds regardless of whether the app called super.
    if @sushi_app.params['partition'].to_s.empty?
      @sushi_app.params['partition'] = SushiConfigHelper.default_partition
    end

    # Override with user-provided parameters (normalize to plain Hash)
    normalized_params = normalize_parameters(@parameters)
    normalized_params.each do |key, value|
      @sushi_app.params[key] = value
    end
  end

  # The dataset-shape gate. Legacy enforces the app's @required_columns twice — in
  # SushiApp#test_run before a script is written, and in the UI, where an app whose required
  # columns the dataset does not satisfy is not offered at all
  # (SushiApplication#required_columns_satisfied_by?). The API had NEITHER, so a mismatched
  # dataset was accepted, written to the DB, sbatched, and only failed inside ezRun. Measured
  # 2026-08-13: Fastqc10x and FastqScreen10x need RawDataDir to be a `.tar` and died 16 s into
  # the job with `all(grepl("\\.tar$", sampleDirs)) is not TRUE`, having already created an
  # output dataset row and a gStore result directory that nothing will ever fill.
  #
  # The column check cannot express "must be a tar", so it would not have caught that exact
  # case — but the class of error is the same one, and a submitter reading "your dataset has no
  # RawDataDir column" gets an answer in a second instead of after a cluster round-trip.
  def validate_required_columns
    report = @sushi_app.required_columns_report
    return true if report[:satisfied]

    present = report[:present].reject(&:empty?)
    detail =
      if report[:mode] == :alternatives
        sets = report[:options].map { |option| "[#{option.join(', ')}]" }.join(' or ')
        "#{@app_name} needs one of these column sets: #{sets}"
      else
        "#{@app_name} needs column(s) #{report[:missing].join(', ')}"
      end

    @errors << "#{detail}. Input dataset #{@dataset_id} has: #{present.join(', ')}."
    Rails.logger.warn("Rejected #{@app_name} submission on dataset #{@dataset_id}: " \
                      "required columns not satisfied (#{report[:mode]})")
    false
  end

  # Legacy-parity gate for the API submit path.
  #
  # The legacy Web UI renders EVERY param as a form control (set_parameters.html.erb
  # iterates @sushi_app.params with no skip list) so the browser always POSTs a resolved
  # scalar: a choice Array arrives as the selected option, a selector Hash as the selected
  # option's value. An app's raw default shape therefore never reaches a job script.
  #
  # The API has no form. Without this step an unspecified selector param is serialized
  # verbatim into the job script and into the output dataset row:
  #     param[['refBuild']] = '{"select"=>"", "Arabidopsis_thaliana/..."=>...}'
  # ezRun rejects that ("special characters not allowed in option string"), so the job dies
  # only AFTER SLURM accepted it and after a corrupt row is already stored. Observed
  # 2026-07-30: STAR on dataset 775, jobs 685/686 -> SLURM 279873/279874 -> FAILED, with
  # refBuild (Hash) and strandMode (Array) unresolved in output dataset 776. 13 of the 16
  # allow-listed legacy apps set refBuild from ref_selector, so this is not STAR-specific.
  #
  # So: resolve the shapes the way the form's default selection would, then apply legacy's
  # own required-param check — run_application_controller.rb:434 refuses a required value
  # that is empty or '-'. Legacy needs no shape check there because its UI cannot produce a
  # Hash/Array; the API can, so the shape is checked too.
  def resolve_and_validate_params
    # Remember which params arrived as an unchosen selector/option list. Resolution runs
    # first, so by validation time the value is just a blank string and that context —
    # the part that tells a caller WHY it is blank — would otherwise be lost.
    @unchosen = {}

    @sushi_app.params.keys.each do |key|
      current = @sushi_app.params[key]
      resolved = resolve_default_selection(key, current)
      @unchosen[key] = current.is_a?(Hash) ? :selector : :option_list if current.is_a?(Hash) || current.is_a?(Array)
      @sushi_app.params[key] = resolved unless resolved.equal?(current)
    end

    unsatisfied = Array(@sushi_app.required_params).select { |key| required_param_unsatisfied?(key) }
    return true if unsatisfied.empty?

    unsatisfied.each do |key|
      @errors << "Required parameter '#{key}' has no value (#{unsatisfied_reason(key)}). " \
                 "Choose one explicitly, e.g. parameters: { \"#{key}\": \"<value>\" }. " \
                 "GET /api/v1/application_configs/#{@normalized_app_name} lists the options."
    end
    Rails.logger.warn("Rejected #{@app_name} submission on dataset #{@dataset_id}: " \
                      "unsatisfied required params #{unsatisfied.inspect}")
    false
  end

  # Mirror the default option the legacy form would have pre-selected.
  def resolve_default_selection(key, value)
    meta = @sushi_app.params.metadata_for(key)
    selected = meta['selected']

    case value
    when Array
      # A multi-selection param is a multiple <select> in the legacy form. Reproduce what
      # that form submits for an untouched page (set_parameters.html.erb + the
      # multi_selection branch of run_application_controller#set_parameters):
      #   pre-selected = `selected` (an Integer indexes into the option list),
      #                  else the WHOLE list when `all_selected` is set,
      #                  else nothing;
      # and the controller joins the submitted options with "," — so the app always sees a
      # STRING, never a Ruby Array, and an empty multi-select arrives as ''.
      #
      # This branch used to return the Array untouched on the assumption that no allow-listed
      # app set the meta. Seven of the sixteen do (DESeq2, EdgeR, CountQC, FeatureCounts,
      # CellRangerMulti x2, Kallisto, ScSeurat x3), and the raw Array reached both the job
      # script and the output dataset row as a Ruby literal
      # ('["protein_coding", "rRNA", ...]'), which made ezRun filter the GTF to nothing:
      # "ERROR: no features were loaded in format GTF".
      if meta['multi_selection']
        chosen = if !selected.nil?
                   selected.is_a?(String) || selected.is_a?(Array) ? selected : value[selected]
                 elsif meta['all_selected']
                   value
                 end
        return Array(chosen).map { |v| v.to_s.strip }.reject(&:empty?).join(',')
      end

      return value[selected] if selected.is_a?(Integer) && selected < value.length
      return selected unless selected.nil?

      value.first
    when Hash
      # Rails `select` pre-selects the first option. ref_selector's first entry is the
      # deliberate 'select' => '' placeholder, i.e. "nothing chosen yet" — which then
      # fails the required-param check below rather than reaching the job script.
      return selected unless selected.nil? || selected.to_s.empty?

      value.values.first
    else
      value
    end
  rescue StandardError => e
    Rails.logger.warn("Could not resolve default selection for param '#{key}': #{e.message}")
    value
  end

  def required_param_unsatisfied?(key)
    value = @sushi_app.params[key]

    if value.is_a?(Array)
      # only legitimate for a multi-selection param, and then only when it holds a value
      return true unless @sushi_app.params.metadata_for(key)['multi_selection']

      return value.reject { |v| v.to_s.strip.empty? }.empty?
    end

    # A Hash here means resolution could not reduce the selector to a choice.
    return true if value.is_a?(Hash)

    stringified = value.to_s.strip
    stringified.empty? || stringified == '-'
  end

  def unsatisfied_reason(key)
    value = @sushi_app.params[key]

    # Shape it arrived as, when that is the real explanation
    case (@unchosen || {})[key]
    when :selector    then return 'an unresolved selector — no option was chosen'
    when :option_list then return 'an unresolved option list — no option was chosen'
    end

    case value
    when ::Hash  then 'an unresolved selector — no option was chosen'
    when ::Array then 'an unresolved option list — no option was chosen'
    when nil     then 'not set'
    else "set to #{value.to_s.strip.inspect}"
    end
  end

  # Build one job unit per sample (SAMPLE mode) or one for the whole dataset.
  # Returns an array of { script_path:, next_dataset: } or nil on failure.
  def build_job_units
    mode = @sushi_app.params['process_mode'].to_s
    mode = 'SAMPLE' if mode.empty? # legacy default

    if mode == 'SAMPLE'
      rows = Array(@sushi_app.dataset_hash)
      if rows.empty?
        @errors << 'No samples in input dataset for SAMPLE-mode app'
        return nil
      end
      rows.each_with_index.map do |row, i|
        # Per-sample: cleaned single-sample hash (tags stripped), as legacy sample_mode.
        @sushi_app.dataset = clean_row(row)
        @sushi_app.last_job = (i == rows.length - 1)
        sample_name = @sushi_app.dataset['Name'] || "sample#{i + 1}"
        build_unit(sample_name, i)
      end
    else
      # DATASET / BATCH: @dataset stays the full array (set by set_input_dataset).
      @sushi_app.last_job = true
      [build_unit(nil, 0)]
    end
  rescue StandardError => e
    @errors << "Failed to generate job scripts: #{e.message}"
    Rails.logger.error("build_job_units error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    nil
  end

  # Write one job script for the app's current @dataset and capture its next_dataset row.
  def build_unit(sample_name, index)
    # Resolve the output row BEFORE writing the script, as legacy does (test_run calls
    # set_output_files -> next_dataset ahead of script generation). Some apps assign
    # parameters inside next_dataset — EdgeR and DESeq2 set @params['comparison'] and
    # @params['name'] there — and the script's `param[[...]]` block is emitted from
    # @params. Generating the script first left those parameters out of the R script
    # entirely, even though they reached parameters.tsv. run_RApp calls next_dataset
    # again for the `output` block, exactly as legacy also calls it twice.
    next_dataset = @sushi_app.next_dataset
    # Legacy's sample_mode/dataset_mode/batch_mode each append the unit's row here
    # (sushiApp.rb:890, :914, :925). It is not bookkeeping: grandchild_datasets reads
    # @result_dataset to learn which samples were actually processed, and falls back to the
    # single @dataset row — which, after a fan-out loop, is only the LAST sample.
    @sushi_app.result_dataset << next_dataset
    script_content = @sushi_app.generate_job_script

    timestamp = Time.now.strftime('%Y%m%d%H%M%S%L')
    parts = [@app_name, @dataset_id, sample_name, "#{timestamp}#{index}"].compact
    script_filename = parts.join('_').gsub(/\s+/, '_') + '.sh'
    script_path = File.join(@sushi_app.job_script_dir, script_filename)

    FileUtils.mkdir_p(@sushi_app.job_script_dir)
    File.write(script_path, script_content)
    FileUtils.chmod(0755, script_path)

    Rails.logger.info("Generated job script: #{script_path}")
    { script_path: script_path, next_dataset: next_dataset }
  end

  # Strip column-name tags (e.g. "Read1 [File]" -> "Read1"), as legacy SUSHI does
  # per sample, so SAMPLE-mode apps can read @dataset['Read1'] / @dataset['Name'].
  def clean_row(row)
    row.each_with_object({}) do |(key, value), acc|
      acc[key.to_s.gsub(/\[.+\]/, '').strip] = value
    end
  end

  # Copy scratch directory to gstore before job submission
  # Uses g-req command for FGCZ environment (gstore is read-only)
  #
  # This copy MUST finish before any row is written — #submit calls it before
  # create_output_dataset and create_job_records on purpose. The job_manager daemon is the job
  # queue: it polls `jobs` and sbatches the script from its gStore path, so a row that exists
  # before its script has landed is a row the daemon can pick up and fail on. That is why the
  # queued form is `g-req -w copy` (wait) and not a fire-and-forget `g-req copy`.
  def copy_scratch_to_gstore
    src = @sushi_app.scratch_result_dir
    dest = @sushi_app.gstore_project_dir

    copy_cmd = SushiConfigHelper.copy_command(src, dest, now: SushiConfigHelper.submit_copy_now?)
    Rails.logger.info("Copying scratch to gstore: #{copy_cmd}")

    status, output = run_bounded_copy(copy_cmd)
    unless status.success?
      detail = if status.exitstatus == TIMEOUT_EXIT_STATUS
                 "timed out after #{SushiConfigHelper.gstore_copy_timeout}s"
               else
                 "exit #{status.exitstatus}"
               end
      @errors << "Failed to copy files from scratch to gstore (#{detail}): #{copy_cmd}"
      # The output is the whole diagnosis and used to be thrown away: a bare system() call
      # discarded it, so an ssh stuck on a password prompt left NOTHING in the log.
      Rails.logger.error("Copy command failed (#{detail}): #{copy_cmd}\n#{output}")
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
  
  # Run a copy command under a wall-clock bound, capturing its combined output.
  #
  # `timeout` is used rather than Ruby's Timeout, because the thing that hangs is a grandchild
  # process (g-req -> gstore-request -> ssh) and Timeout only unwinds the Ruby frame, leaving
  # the child running and the request half-done. -k also KILLs a child that ignores TERM.
  def run_bounded_copy(copy_cmd)
    bounded = "timeout -k 30 #{SushiConfigHelper.gstore_copy_timeout} #{copy_cmd}"
    output, status = Open3.capture2e(bounded)
    [status, output]
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

  def create_parameters_tsv
    # job_manager expects parameters.tsv at: dirname(dirname(script_path))/parameters.tsv
    # In scratch, this is scratch_result_dir/parameters.tsv. @params are identical
    # across samples, so a single shared parameters.tsv covers all per-sample scripts.
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

  # Mirror of legacy SushiApp#save_next_dataset_as_tsv: headers are the union of every
  # row's keys in first-seen order, and an empty value is written as an empty field.
  def create_next_dataset_tsv(next_datasets)
    rows = Array(next_datasets).compact
    return if rows.empty?

    dataset_file = File.join(@sushi_app.scratch_result_dir, 'dataset.tsv')
    headers = rows.flat_map(&:keys).uniq

    CSV.open(dataset_file, 'w', col_sep: "\t") do |out|
      out << headers
      rows.each do |row|
        out << headers.map { |header| row[header].to_s.empty? ? nil : row[header] }
      end
    end

    Rails.logger.info("Created dataset.tsv: #{dataset_file}")
  rescue StandardError => e
    Rails.logger.error("Failed to create dataset.tsv: #{e.message}")
    # Don't fail the job submission if dataset.tsv creation fails
  end

  def create_output_dataset(next_datasets)
    next_datasets = Array(next_datasets).compact
    if next_datasets.empty?
      @errors << 'No output rows produced by the application'
      return false
    end

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

    # Headers from the first row; every row is projected onto that column order so a
    # SAMPLE-mode dataset (one row per sample) is stored as N consistent rows.
    headers = next_datasets.first.keys
    rows = next_datasets.map { |nd| headers.map { |h| nd[h] } }

    # Save to database
    @output_dataset_id = DataSet.save_dataset_to_database(
      data_set_arr: data_set_arr,
      headers: headers,
      rows: rows,
      user: @user,
      child: false,
      # Legacy writes the app's CLASS name here (sushiApp.rb:1039 `self.class.name`), not the
      # short name the REST API and LegacyAppLoader accept. Legacy's dataset filter matches
      # this by regex and B-Fabric registration passes it as --sushi-app, so the short form
      # would hide New SUSHI's datasets from the legacy UI and misreport the app to B-Fabric.
      sushi_app_name: @sushi_app.class.name
    )

    @output_dataset = DataSet.find(@output_dataset_id)
    
    # Save parameters in the output dataset (normalize and skip validation).
    # legacy_output_params, not @parameters: the record must say what the run USED.
    @output_dataset.job_parameters = normalize_parameters(legacy_output_params)
    @output_dataset.save(validate: false)

    Rails.logger.info("Created output dataset: #{@output_dataset_id}")
    true
  rescue StandardError => e
    @errors << "Failed to create output dataset: #{e.message}"
    Rails.logger.error("Output dataset creation error: #{e.message}\n#{e.backtrace.join("\n")}")
    false
  end

  # Port of legacy save_grandchild_datasets_to_database (sushiApp.rb:935-985).
  #
  # A grandchild is an EXTRA dataset the run produces, hanging one level below the output
  # dataset: ParentID is the output dataset, not the input. Legacy makes it ONE dataset holding
  # every grandchild row (its tsv loop appends a single path), names it from
  # params['grandchildName'], else the first row's Name, else "<app>_grandchild_1", and forces
  # the child flag when @grandchild is set — which it is by default.
  #
  # New SUSHI simply never did this, so any app declaring grandchild_datasets silently lost
  # them: the rows were neither persisted nor copied to gStore, which is also why the footer
  # had nothing to copy (noted as a deliberate gap when task #6 landed). Closing it matters for
  # downstream chaining — a grandchild is what a next app consumes. Of the allow-listed apps
  # only a MULTIPLEXED CellRangerMulti run produces one today.
  #
  # Never fails the submission: the jobs and the output dataset are already committed by this
  # point, so a grandchild problem is reported and logged, not raised.
  def create_grandchild_datasets
    return true if @grandchild_tsv.nil?

    rows = @grandchild_tsv[:rows]
    headers = @grandchild_tsv[:headers]
    name = [@sushi_app.params['grandchildName'], rows.first['Name'],
            "#{@sushi_app.name}_grandchild_1"].find { |candidate| candidate.to_s.strip.present? }

    data_set_arr = [
      'DataSetName', name.to_s.strip,
      'ProjectNumber', @input_dataset.project.number.to_s,
      'ParentID', @output_dataset_id.to_s,
      'Comment', 'autogenerated grandchild'
    ]

    @grandchild_dataset_id = DataSet.save_dataset_to_database(
      data_set_arr: data_set_arr,
      headers: headers,
      rows: rows.map { |row| headers.map { |header| row[header] } },
      user: @user,
      child: @sushi_app.grandchild ? true : !!@sushi_app.child,
      sushi_app_name: @sushi_app.class.name # same class name as the output dataset (see above)
    )
    Rails.logger.info("Created grandchild dataset: #{@grandchild_dataset_id} " \
                      "(#{rows.length} row(s), parent #{@output_dataset_id})")
    true
  rescue StandardError => e
    @errors << "Output dataset was created but the grandchild dataset failed: #{e.message}"
    Rails.logger.error("Grandchild dataset creation error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    false
  end

  # Legacy's @output_params (sushiApp.rb:354-356): the app's fully-resolved parameter set
  # plus the app class name under 'sushi_app'. Legacy persists exactly this on the output
  # dataset (sushiApp.rb:931), so a dataset records what the run actually used — defaults
  # included — rather than only the arguments the caller happened to pass.
  #
  # By this point resolve_and_validate_params has already written the resolved values back
  # into @sushi_app.params, so these are scalars; the Array guard is a belt-and-braces
  # fallback matching create_parameters_tsv.
  #
  # Deliberately NOT the same content as parameters.tsv: that file additionally carries
  # dataRoot and resultDir for the job_manager, and legacy writes neither of them into
  # job_parameters.
  def legacy_output_params
    # .to_h first: the shim's params object exposes #each/#keys but does not include
    # Enumerable, so #each_with_object is not available on it.
    resolved = @sushi_app.params.to_h.each_with_object({}) do |(key, value), acc|
      acc[key] = value.is_a?(Array) ? value.first : value
    end
    resolved['sushi_app'] = @sushi_app.class.name
    resolved
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

  # One Job record per unit. All share the single output dataset (next_dataset_id)
  # and the input dataset; each carries its own gstore script path. #job stays the
  # first record for backward-compatible callers; #jobs exposes them all.
  def create_job_records(units)
    @jobs = []
    units.each do |unit|
      gstore_script_path = File.join(@sushi_app.gstore_script_dir, File.basename(unit[:script_path]))
      job = Job.new(
        script_path: gstore_script_path,
        next_dataset_id: @output_dataset_id,
        input_dataset_id: @input_dataset.id,
        status: 'CREATED',
        user: @sushi_app.user
      )

      unless job.save
        @errors << "Failed to save job: #{job.errors.full_messages.join(', ')}"
        return false
      end
      Rails.logger.info("Created job record: #{job.id}")
      @jobs << job
    end

    @job = @jobs.first
    true
  rescue StandardError => e
    @errors << "Failed to create job record: #{e.message}"
    false
  end
end

