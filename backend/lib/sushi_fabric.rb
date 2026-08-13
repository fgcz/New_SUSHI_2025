# SushiFabric - SUSHI Application Framework
# Provides classes and methods to load and run SUSHI App classes
# Compatible with old SUSHI system

require 'csv' # grandchild_dataset.tsv, as legacy writes it
require_relative 'global_variables'

module SushiFabric
  # Legacy compatibility constants. Some legacy apps (and backend/app/models/data_set.rb)
  # reference SushiFabric::GSTORE_DIR / SushiFabric::SCRATCH_DIR directly. Resolve them
  # from the same config source as the instance-level dirs.
  GSTORE_DIR = SushiConfigHelper.gstore_dir unless defined?(GSTORE_DIR)
  SCRATCH_DIR = SushiConfigHelper.scratch_dir unless defined?(SCRATCH_DIR)

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
                  :result_dir_base,
                  # Legacy sushiApp.rb:215/237: @grandchild forces the child flag on a
                  # grandchild dataset, @child carries it for a normal one.
                  :grandchild, :child
    attr_reader :params
    
    def initialize
      @name = ''
      @analysis_category = ''
      @description = ''
      @required_columns = []
      @required_params = []
      @params = SushiParams.new
      # Legacy SUSHI defaults process_mode to SAMPLE (one job per sample). Apps that
      # want whole-dataset processing set @params['process_mode'] = 'DATASET' in their
      # own initialize (after super). Matching this default is what lets SAMPLE-mode
      # apps (which never set process_mode explicitly) fan out correctly.
      @params['process_mode'] = 'SAMPLE'
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
      @grandchild = true # legacy default (sushiApp.rb:237)
      @child = nil
    end
    
    # Set input dataset from database
    def set_input_dataset
      return unless @dataset_sushi_id
      
      dataset_record = DataSet.find_by_id(@dataset_sushi_id)
      return unless dataset_record
      
      @dataset_hash = dataset_record.samples.map { |sample| sample.to_hash }
      # Mirror legacy SushiApp#set_input_dataset: @dataset is the FULL array of sample
      # hashes (tagged keys) in every mode. set_default_parameters runs against this
      # array (e.g. @dataset[0]['refBuild']); in SAMPLE mode JobSubmissionService then
      # reassigns @dataset to each cleaned single-sample hash before generating that
      # sample's script and next_dataset.
      @dataset = @dataset_hash

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

    # Port of legacy SushiApp#check_required_columns (sushiApp.rb:334-350), which the API path
    # had no equivalent of at all. Legacy enforces this twice: in #test_run before a job is
    # written, and in the UI, where SushiApplication#required_columns_satisfied_by? decides
    # whether the app is even offered for a dataset. Without it a submission whose dataset
    # lacks a required column is accepted, reaches SLURM, and dies inside ezRun — measured
    # 2026-08-13 on Fastqc10x and FastqScreen10x, which need a .tar RawDataDir and failed 16 s
    # into the job with `all(grepl("\\.tar$", sampleDirs)) is not TRUE`.
    #
    # Returns a report rather than legacy's bare boolean, because the caller has to tell the
    # submitter WHICH column is missing — legacy can be terse, it has the whole form in front
    # of the user.
    #
    # Two shapes, as legacy: a flat list is AND (every column required), a list of lists is
    # ALTERNATIVES (CellRangerMultiApp is the only allow-listed app using it:
    # [['Name','RawDataDir','Species'], ['Name','Read1','Read2','Species']]).
    #
    # DELIBERATE DEVIATION, the only one: legacy counts satisfied alternatives and demands
    # `satisfied_options == 1`, so a dataset carrying BOTH alternatives is rejected. We accept
    # it (>= 1). Reason, measured: ds 819 declares RawDataDir *and* Read1/Read2 and its
    # CellRangerMulti run completed correctly, because ezRun resolves the ambiguity itself and
    # deterministically prefers Read1 (app-cellRangerMulti.R:201-208). Legacy's `== 1` reads as
    # a typo for "at least one"; rejecting a superset serves no purpose this gate exists for —
    # it catches MISSING columns, and a superset is not a missing column. Flip the comparison
    # in satisfied_options if strict legacy parity is ever wanted.
    def required_columns_report
      present = Array(@dataset_hash).flat_map { |row| row.respond_to?(:keys) ? row.keys : [] }
                                    .uniq.map { |col| normalize_column_name(col) }
      required = Array(@required_columns)
      return { satisfied: true, mode: :none, present: present } if required.empty?

      if required.all? { |entry| entry.is_a?(Array) }
        options = required.map { |option| Array(option).map { |req| normalize_column_name(req) } }
        satisfied = options.select { |option| (option - present).empty? }
        { satisfied: satisfied.any?, mode: :alternatives, options: options,
          satisfied_options: satisfied, present: present }
      else
        missing = required.map { |req| normalize_column_name(req) } - present
        { satisfied: missing.empty?, mode: :all, missing: missing, present: present }
      end
    end

    # Legacy's boolean, kept under legacy's name for anything that only needs the verdict.
    def check_required_columns
      required_columns_report[:satisfied]
    end

    # Legacy strips the tag from the dataset side in both branches and from the required side
    # only in the alternatives branch (sushiApp.rb:344 vs :348). Apps author required_columns
    # untagged, so normalizing both sides changes nothing for any allow-listed app and removes
    # the inconsistency.
    def normalize_column_name(name)
      name.to_s.gsub(/\[.+\]/, '').strip
    end
    
    # LEGACY CONTRACT (sushiApp.rb:507): set_dir_paths runs @name.gsub!(/\s/,'_') BEFORE it
    # derives any path from the app name, because those paths are emitted into the job script
    # unquoted. Three of the 17 allow-listed legacy apps carry a space in @name —
    # 'RNA BamStats', 'DNA BamStats', 'samtools mpileup' — and without this rule every one of
    # them died on line 8 of its own script: `SCRATCH_DIR=/scratch/rna bamstats_..._temp$$`
    # is not an assignment, it is the assignment `SCRATCH_DIR=/scratch/rna` prefixed to the
    # command `bamstats_..._temp$$` (observed on fgcz-h-083, job 760:
    # "line 8: bamstats_2026-08-13--09-05-03_temp582741: command not found"). The same space
    # also splits the footer's `rm -rf` into TWO arguments relative to /scratch.
    #
    # The name reaches paths by three routes, which is why the rule belongs here and not at
    # one call site: the scratch temp dir, @result_dir_base when no next_dataset_name was
    # given (so the gStore result dir, param[['resultDir']] and every output [File] value
    # would contain a space — g-req cannot transfer those at all), and the default output
    # row name. Idempotent, so both the shim and JobSubmissionService can call it.
    def normalize_name!
      @name = @name.to_s.gsub(/\s/, '_')
    end

    # LEGACY CONTRACT (sushiApp.rb:548-552): the scratch temp dir is the run's OWN
    # @result_dir_base with '_temp$$' appended, plus the row's Name in SAMPLE mode — not a
    # separately invented name. The shim built "#{@name.downcase}_#{Time.now}_temp$$", which
    # (a) re-derived from the raw app name after prepare_result_dir had sanitized it,
    # (b) took a SECOND Time.now, so the temp dir carried a different timestamp than the
    # result dir it belongs to, and (c) lost the sample, leaving a fan-out's leftover scratch
    # dirs on the node unattributable to a run or a sample when a job died before cleanup.
    # A Hash @dataset IS legacy's SAMPLE unit (JobSubmissionService assigns the cleaned row
    # per sample); in DATASET mode @dataset is the full array, where a 'Name' lookup would
    # raise. The @result_dir_base fallback covers callers that generate a script without
    # prepare_result_dir (specs do).
    def scratch_temp_dir_name
      base = @result_dir_base ||
             "#{@name}_#{@dataset_sushi_id}_#{Time.now.strftime('%Y-%m-%d--%H-%M-%S')}"
      sample = @dataset['Name'] if @dataset.is_a?(Hash)
      [base, sample, 'temp$$'].compact.reject { |part| part.to_s.empty? }.join('_')
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
      script << "SCRATCH_DIR=#{File.join(@scratch_dir, scratch_temp_dir_name)}"
      script << "GSTORE_DIR=#{@gstore_dir}"
      script << "INPUT_DATASET=#{@input_dataset_tsv_path}"
      script << "LAST_JOB=#{@last_job.to_s.upcase}"
      script << 'echo "Job runs on `hostname`"'
      script << 'echo "at $SCRATCH_DIR"'
      # Quoted, where legacy (sushiApp.rb:593-594) is bare. The value is the same; this is
      # the one deliberate deviation, and it exists because the expansion is the only place
      # a dataset-supplied string (the SAMPLE row's Name) reaches a `rm -rf` argument list.
      script << 'mkdir "$SCRATCH_DIR" || exit 1'
      script << 'cd "$SCRATCH_DIR" || exit 1'
      
      # Load modules, pinned to the concrete versions lmod resolves right now
      if @modules && !@modules.empty? && !module_source.to_s.empty?
        script << "source #{module_source}"
        resolved = resolve_module_versions
        if resolved.length == @modules.length
          script << "module add #{resolved.join(' ')}"
        else
          # Legacy emits NO module add line rather than a half-resolved one, so the
          # failure is loud in the job log instead of silently loading the wrong tools.
          Rails.logger.error('#' * 100)
          Rails.logger.error('# Error in checking modules')
          Rails.logger.error("# Please check if all modules are correctly installed, " \
                             "searched #{@modules.join(',')} but only detected #{resolved.join(',')}")
          Rails.logger.error('#' * 100)
        end
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
      script.concat(gstore_copy_lines)
      script.concat(grandchild_copy_lines)
      script << "cd #{@scratch_dir}"
      script << 'rm -rf "$SCRATCH_DIR" || exit 1'
      script << ""
      
      script.join("\n")
    end

    # The gStore copy footer. Port of legacy SushiApp#job_footer
    # (sushi_fabric/sushiApp.rb:600-648): copy the app's DECLARED outputs, nothing else.
    #
    # This replaced `for f in *; do ... done`, which published the entire scratch temp
    # dir. Measured on real runs: 93% of a STAR result dir was undeclared payload
    # (trimmed FASTQs, fastp.html/json, adapters.fa, Log.out, SJ.out.tab), FeatureCounts
    # re-published a name-sorted copy of its own input BAM, and every SAMPLE-mode job
    # raced the others writing identically-named intermediates to the same destination.
    # Legacy has never copied any of it — the undeclared files die with the `rm -rf`.
    #
    # Three deliberate choices, each of which the glob got wrong:
    #
    # * NO `[ -e ]` guard, matching legacy. With a declared list, skipping a missing file
    #   would mean a job that silently reports COMPLETED without its output and then
    #   destroys the scratch evidence. ezRun codes to the unguarded contract on purpose
    #   (app-mapping.R: "the copy of the finished workunit crashes on the first missing
    #   file"; renameOrCreate exists to create empty placeholders for exactly this).
    # * BATCHED into one g-req when every output shares a destination, matching legacy
    #   (dest_dirs.uniq.length == 1 and greq). gtools' _transfer loops over sources and
    #   does not abort on one failure, so batching is no less safe — and the per-file
    #   `g-req -w` loop cost 9m20s of serial waits on an 11-file job.
    # * BARE, UNQUOTED basenames, matching legacy. Client-side quoting cannot survive
    #   /usr/local/ngseq/bin/g-req, whose last line passes UNQUOTED `$@` to gstore-request;
    #   the old `\"$f\"` therefore shipped literal quote characters all the way into the
    #   transfer daemon's argv. Filenames containing whitespace are broken by g-req itself,
    #   not by us, and no quoting here can fix that.
    def gstore_copy_lines
      copies = declared_output_copies
      if copies.empty?
        Rails.logger.error(
          "#{@name}: no [File]-tagged headers in next_dataset, so nothing will be copied " \
          'to gStore. Legacy warns about the same condition (sushiApp.rb:1334-1338).'
        )
        return ['# no declared output files - nothing to copy']
      end

      dest_dirs = copies.map(&:last).uniq
      # Legacy batches only when the configured server speaks g-req (its `greq` probe).
      if dest_dirs.size == 1 && SushiConfigHelper.copy_method == 'g-req'
        [SushiConfigHelper.copy_command(copies.map(&:first).join(' '), dest_dirs.first)]
      else
        copies.map { |src, dest| SushiConfigHelper.copy_command(src, dest) }
      end
    end

    # Legacy's grandchild hook (sushiApp.rb:656-660): apps override it to declare an EXTRA
    # dataset the job will produce alongside next_dataset, one level deeper in the tree.
    # Default empty, as legacy.
    #
    # It is predicted at SUBMIT time from the app's own Ruby, exactly like next_dataset — it is
    # NOT read back from the job's output. Of the 17 allow-listed apps only CellRangerMultiApp
    # defines it, and only when TenXLibrary includes 'Multiplexing' and the order's
    # o<id>_metaData directory exists, so a plain GEX run legitimately produces none.
    def grandchild_datasets
      []
    end

    # Legacy job_footer's grandchild half (sushiApp.rb:632-641). Every [File]-tagged value in
    # every grandchild row gets its OWN copy command — legacy does not batch these even when
    # the destinations coincide, and this is the un-batched loop it uses. Kept un-batched so a
    # grandchild whose files land in per-sample subdirectories still copies correctly.
    def grandchild_copy_lines
      Array(grandchild_datasets).flat_map do |row|
        next [] unless row.respond_to?(:keys)

        row.keys.filter_map do |header|
          next unless header.to_s.tag?('File')

          value = row[header].to_s
          next if value.empty?

          SushiConfigHelper.copy_command(File.basename(value),
                                         File.dirname(File.join(@gstore_dir, value)))
        end
      end
    end

    # Legacy save_grandchild_datasets_as_tsv (sushiApp.rb:759-793): ONE grandchild_dataset.tsv
    # in the result dir holding every grandchild row, with the union of all rows' keys as the
    # header and blanks written as nil. Lands in gStore because the whole scratch result dir is
    # copied there at submit. Returns the rows it wrote (nil when there are none) so the caller
    # does not have to call the app's hook twice.
    def write_grandchild_dataset_tsv
      rows = Array(grandchild_datasets).select { |row| row.respond_to?(:keys) }
      return nil if rows.empty? || @scratch_result_dir.nil?

      headers = rows.flat_map(&:keys).uniq
      path = File.join(@scratch_result_dir, 'grandchild_dataset.tsv')
      CSV.open(path, 'w', col_sep: "\t") do |out|
        out << headers
        rows.each do |row|
          out << headers.map { |header| row[header].to_s.empty? ? nil : row[header] }
        end
      end
      { path: path, headers: headers, rows: rows }
    end

    # [[source_basename, destination_dir], ...] for every next_dataset header tagged
    # [File], in declaration order. Legacy derives this set the same way in
    # set_output_files (sushiApp.rb:322-333) — no app declares it by hand; a grep for
    # `output_files` over all 17 allow-listed legacy apps returns zero hits.
    #
    # The project-relative -> scratch bridge is legacy's exactly (sushiApp.rb:614-615):
    # the source is File.basename(value) because the job's cwd IS the scratch temp dir,
    # and the destination is File.dirname(gstore_dir + value).
    #
    # Legacy computes the HEADER set once with @dataset blanked to {} in SAMPLE mode and
    # the VALUES again per row. We use one per-row next_dataset for both: it yields the
    # same headers for every allow-listed app, and it avoids legacy's blanking hazard
    # (an app that indexes @dataset inside next_dataset raises on the blanked call).
    def declared_output_copies
      row = next_dataset
      return [] unless row.respond_to?(:keys)

      row.keys.filter_map do |header|
        next unless header.to_s.tag?('File')

        value = row[header].to_s
        next if value.empty?

        dest_dir = File.dirname(File.join(@gstore_dir, value))
        unless dest_dir == @gstore_result_dir
          # Either an absolute value (the pre-9663a8c result_dir bug) or an output
          # declared inside a subdirectory, for which legacy's basename/dirname pair
          # disagree. Neither occurs in the allow-listed apps; say so loudly if it starts.
          Rails.logger.warn(
            "#{@name}: declared output #{header.inspect} => #{value.inspect} resolves to " \
            "#{dest_dir}, not the result dir #{@gstore_result_dir}. The source is looked " \
            'up by basename in the scratch root, so this copy may not do what the app means.'
          )
        end
        [File.basename(value), dest_dir]
      end
    end

    # lmod profile to source in job scripts and to query for module versions.
    def module_source
      @module_source ||= Rails.application.config.try(:module_source).to_s
    end

    # Resolve each requested module to the concrete version lmod currently defaults to,
    # e.g. "Aligner/kallisto" -> "Aligner/kallisto/0.51.1". Port of legacy
    # SushiApp#check_latest_modules_version: one `module whatis` for the whole list, keep
    # the first whitespace-delimited field of each line, drop anything that is not one of
    # the requested modules (the login profile prints unrelated banner lines).
    #
    # WHY this must not stay a stub: an unversioned `module add Aligner/kallisto` loads
    # whatever the cluster currently defaults to, so the same job silently produces
    # different numbers as the cluster moves. Measured 2026-08-06: a Kallisto run
    # reproduced the legacy oracle's inputs and parameters exactly but returned different
    # eff_length/tpm, because the oracle pinned 0.46.1 and the current default is 0.51.1.
    # Recording the resolved version makes a run reproducible after the fact.
    #
    # Memoized: legacy re-runs the shell-out for every script of a SAMPLE fan-out; the
    # module list cannot change between samples of one submission, so once is enough.
    def resolve_module_versions
      return @resolved_module_versions if @resolved_module_versions
      return (@resolved_module_versions = []) if @modules.blank? || module_source.empty?

      wanted = Regexp.union(@modules.map { |m| m.to_s.strip }.reject(&:empty?))

      @resolved_module_versions =
        module_whatis_output.to_s.split("\n").map(&:chomp).reject(&:empty?).select { |l| l =~ wanted }
    rescue StandardError => e
      Rails.logger.error("Module version resolution failed: #{e.message}")
      @resolved_module_versions = []
    end

    # The lmod query itself, isolated so it can be stubbed and so the shell command lives
    # in one place. Returns one candidate per line, already reduced to its first field.
    def module_whatis_output
      `bash -lc "source #{module_source}; module whatis #{@modules.join(' ')} 2>&1" | cut -f 1 -d " " | uniq`
    end
    
    # Prepare result directory paths (scratch and gstore)
    def prepare_result_dir
      # Legacy's set_dir_paths sanitizes @name here, before deriving anything from it.
      normalize_name!

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

      # Project directory name ("p35611"), or "results" for a dataset with no project.
      @project = dataset&.project ? "p#{dataset.project.number}" : 'results'

      # LEGACY CONTRACT (sushiApp.rb#set_dir_paths): @result_dir and @gstore_result_dir
      # are two DIFFERENT things and must not be collapsed.
      #   @result_dir        = "p35611/<run>"                     PROJECT-RELATIVE
      #   @gstore_result_dir = "/srv/gstore/projects/p35611/<run>" ABSOLUTE
      # Apps embed @result_dir in their output dataset [File]/[Link] values and it is
      # emitted as param[['resultDir']]; the gStore web layer builds URLs as
      # "https://fgcz-gstore.uzh.ch/projects/" + that value. Making it absolute produced
      # ".../projects//srv/gstore/projects/..." links and dataset rows that downstream
      # apps could not resolve against dataRoot. Only @gstore_* are filesystem paths.
      @result_dir = File.join(@project, @result_dir_base)

      @gstore_project_dir = File.join(@gstore_dir, @project)
      @gstore_result_dir = File.join(@gstore_dir, @result_dir)
      @gstore_script_dir = File.join(@gstore_result_dir, 'scripts')
      
      # Create scratch directory (local, writable)
      FileUtils.mkdir_p(@scratch_result_dir)
      FileUtils.mkdir_p(@scratch_script_dir)
      
      Rails.logger.info("Prepared scratch directory: #{@scratch_result_dir}")
      Rails.logger.info("Target gstore directory: #{@gstore_result_dir}")
    end
    
    # Hook legacy apps override to finish setting themselves up once the input dataset,
    # the result dir and the parameters are known but before anything is validated or
    # generated (legacy SushiApp#preprocess, called from run -> test_run). Apps use it to
    # seed @random_string for their Live Report link, to add 'Read2' to @required_columns
    # for a paired run, and to append @required_params. Base implementation does nothing.
    def preprocess
      # this should be overwritten in a subclass
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

    # Hash-compatible helpers some legacy apps call on @params directly.
    def has_key?(key)
      @params.key?(key)
    end
    alias include? has_key?

    def values
      @params.values
    end

    def empty?
      @params.empty?
    end

    # Remove a param (and any metadata) — mirrors Hash#delete; returns the value.
    def delete(key)
      @metadata.delete(key)
      @params.delete(key)
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
