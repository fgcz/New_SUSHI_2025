require 'rails_helper'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Focused unit coverage for the SAMPLE-mode fan-out logic (legacy parity: one job
# unit per sample) and DATASET single-unit behavior. Uses a lightweight fake app so
# no DB/gstore is touched; end-to-end submission is exercised via the request specs.
RSpec.describe JobSubmissionService do
  # Minimal stand-in for a loaded SushiApp exposing just the surface build_job_units uses.
  let(:fake_app_class) do
    Class.new do
      attr_accessor :dataset, :last_job
      attr_reader :params, :dataset_hash, :job_script_dir

      def initialize(mode:, rows:, dir:)
        @params = { 'process_mode' => mode }
        @dataset_hash = rows
        @job_script_dir = dir
        @dataset = rows # set_input_dataset leaves @dataset as the full array
      end

      def generate_job_script
        tag = @dataset.is_a?(Hash) ? @dataset['Name'] : 'DATASET'
        "#!/bin/bash\n# #{tag}\n"
      end

      def next_dataset
        name = @dataset.is_a?(Hash) ? @dataset['Name'] : 'result'
        { 'Name' => name, 'Out [File]' => "path/#{name}" }
      end
    end
  end

  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  def service_for(app)
    svc = described_class.new(dataset_id: 1, app_name: 'X', parameters: {}, user: 'u')
    svc.instance_variable_set(:@sushi_app, app)
    svc.instance_variable_set(:@app_name, 'X')
    svc.instance_variable_set(:@dataset_id, 1)
    svc
  end

  describe '#build_job_units' do
    it 'produces one unit per sample in SAMPLE mode, each with its own script' do
      rows = [{ 'Name' => 's1', 'Read1 [File]' => 'a' }, { 'Name' => 's2', 'Read1 [File]' => 'b' }]
      units = service_for(fake_app_class.new(mode: 'SAMPLE', rows: rows, dir: tmpdir)).send(:build_job_units)

      expect(units.size).to eq(2)
      expect(units.map { |u| u[:next_dataset]['Name'] }).to eq(%w[s1 s2])
      expect(units).to all(satisfy { |u| File.exist?(u[:script_path]) })
      expect(units.map { |u| u[:script_path] }.uniq.size).to eq(2)
    end

    it 'produces a single unit in DATASET mode regardless of sample count' do
      rows = [{ 'Name' => 's1' }, { 'Name' => 's2' }]
      units = service_for(fake_app_class.new(mode: 'DATASET', rows: rows, dir: tmpdir)).send(:build_job_units)

      expect(units.size).to eq(1)
      expect(units.first[:next_dataset]['Name']).to eq('result')
    end

    it 'defaults an unset process_mode to SAMPLE (legacy default)' do
      rows = [{ 'Name' => 's1' }, { 'Name' => 's2' }]
      units = service_for(fake_app_class.new(mode: '', rows: rows, dir: tmpdir)).send(:build_job_units)

      expect(units.size).to eq(2)
    end

    # Legacy resolves the output row before writing the script (test_run calls
    # set_output_files -> next_dataset ahead of script generation). EdgeR and DESeq2 assign
    # @params['comparison'] and @params['name'] inside next_dataset, and the script's
    # param[[...]] block is emitted from @params — so generating the script first dropped
    # those parameters from the R script entirely (found in the EdgeR Level-2 diff,
    # 2026-08-06).
    it 'calls next_dataset before generating the script, so params it sets reach the script' do
      late_param_app = Class.new do
        attr_accessor :dataset, :last_job
        attr_reader :params, :dataset_hash, :job_script_dir

        def initialize(dir)
          @params = { 'process_mode' => 'DATASET' }
          @dataset_hash = [{ 'Name' => 's1' }]
          @dataset = @dataset_hash
          @job_script_dir = dir
        end

        def next_dataset
          @params['comparison'] = 'Treated--over--Control'
          { 'Name' => @params['comparison'] }
        end

        # Stands in for run_RApp: the param block is rendered from @params at this moment.
        def generate_job_script
          @params.map { |k, v| "param[['#{k}']] = '#{v}'" }.join("\n")
        end
      end

      units = service_for(late_param_app.new(tmpdir)).send(:build_job_units)
      script = File.read(units.first[:script_path])

      expect(script).to include("param[['comparison']] = 'Treated--over--Control'")
      expect(units.first[:next_dataset]['Name']).to eq('Treated--over--Control')
    end
  end

  describe '#clean_row' do
    it 'strips column-name tags so per-sample keys are untagged' do
      svc = described_class.new(dataset_id: 1, app_name: 'X', parameters: {}, user: 'u')
      cleaned = svc.send(:clean_row, 'Read1 [File]' => 'x', 'Name' => 'n', 'Genotype [Factor]' => 'mut')
      expect(cleaned).to eq('Read1' => 'x', 'Name' => 'n', 'Genotype' => 'mut')
    end
  end

  # The legacy Web UI resolves every param to a scalar before POSTing, so an app's raw
  # default shape (a ref_selector Hash, a choice Array) can never reach a job script. The
  # API has no form, so the service resolves the same default selection and then applies
  # legacy's required-param check (run_application_controller.rb:434: empty or '-' fails).
  #
  # Regression for the 2026-07-30 failure: STAR submitted with parameters: {} wrote
  # param[['refBuild']] = '{"select"=>"", ...}' into the job script and into output dataset
  # 776, SLURM accepted jobs 279873/279874, and ezRun then died on the option string.
  describe '#resolve_and_validate_params' do
    let(:selector) do
      { 'select' => '',
        'Mus_musculus/Ensembl/GRCm39' => 'Mus_musculus/Ensembl/GRCm39',
        'Homo_sapiens/GENCODE/GRCh38' => 'Homo_sapiens/GENCODE/GRCh38' }
    end

    # A real SushiApp: its #params is a SushiParams, which is what carries the metadata the
    # resolver consults. A plain Hash would not exercise the same code path.
    def app_with(params, required: [])
      app = SushiFabric::SushiApp.new
      params.each { |k, v| app.params[k] = v }
      app.required_params = required
      app
    end

    def gate(app)
      svc = described_class.new(dataset_id: 1, app_name: 'STAR', parameters: {}, user: 'u')
      svc.instance_variable_set(:@sushi_app, app)
      svc.instance_variable_set(:@normalized_app_name, 'STAR')
      [svc.send(:resolve_and_validate_params), svc]
    end

    it 'rejects a required selector param that was never chosen, naming it' do
      app = app_with({ 'refBuild' => selector }, required: ['refBuild'])
      ok, svc = gate(app)

      expect(ok).to be false
      expect(svc.errors.join).to include("Required parameter 'refBuild'")
      expect(svc.errors.join).to include('unresolved selector')
    end

    it 'does not write the raw selector Hash anywhere when it rejects' do
      app = app_with({ 'refBuild' => selector }, required: ['refBuild'])
      gate(app)

      # resolution collapsed it to the placeholder rather than leaving a Hash behind
      expect(app.params['refBuild']).to eq('')
    end

    it 'resolves a choice Array to its first option, as the form pre-selects it' do
      app = app_with({ 'strandMode' => %w[both sense antisense] }, required: ['strandMode'])
      ok, = gate(app)

      expect(ok).to be true
      expect(app.params['strandMode']).to eq('both')
    end

    it 'leaves a caller-chosen scalar untouched and accepts it' do
      app = app_with({ 'refBuild' => 'Mus_musculus/Ensembl/GRCm39' }, required: ['refBuild'])
      ok, = gate(app)

      expect(ok).to be true
      expect(app.params['refBuild']).to eq('Mus_musculus/Ensembl/GRCm39')
    end

    it "rejects '-' in a required param, matching the legacy check" do
      app = app_with({ 'refBuild' => '-' }, required: ['refBuild'])
      ok, svc = gate(app)

      expect(ok).to be false
      expect(svc.errors.join).to include('"-"')
    end

    it 'resolves a NON-required selector without blocking the submission' do
      app = app_with({ 'refBuild' => selector, 'paired' => true }, required: ['paired'])
      ok, = gate(app)

      expect(ok).to be true
      expect(app.params['refBuild']).to eq('') # collapsed, so never serialized as a Hash
    end

    it 'honours an explicit selected meta over the placeholder' do
      app = app_with({ 'refBuild' => selector }, required: ['refBuild'])
      app.params['refBuild', 'selected'] = 'Homo_sapiens/GENCODE/GRCh38'
      ok, = gate(app)

      expect(ok).to be true
      expect(app.params['refBuild']).to eq('Homo_sapiens/GENCODE/GRCh38')
    end

    # A multi_selection param is a multiple <select>; the legacy form joins the submitted
    # options with "," so the app sees a String. Leaving it a Ruby Array serialized
    # '["protein_coding", "rRNA", ...]' into the job script and the output dataset row and
    # made ezRun filter the GTF to nothing (FeatureCounts Level-2, 2026-08-06).
    it 'resolves a multi_selection param to its `selected` option, joined' do
      app = app_with({ 'kits' => %w[a b c] })
      app.params['kits', 'multi_selection'] = true
      app.params['kits', 'selected'] = 'a'
      ok, = gate(app)

      expect(ok).to be true
      expect(app.params['kits']).to eq('a')
    end

    it 'joins an Array `selected` with commas, as the form submits it' do
      app = app_with({ 'kits' => %w[a b c] })
      app.params['kits', 'multi_selection'] = true
      app.params['kits', 'selected'] = %w[a c]
      gate(app)

      expect(app.params['kits']).to eq('a,c')
    end

    it 'treats a non-String/Array `selected` as an index into the option list' do
      app = app_with({ 'kits' => %w[a b c] })
      app.params['kits', 'multi_selection'] = true
      app.params['kits', 'selected'] = 2
      gate(app)

      expect(app.params['kits']).to eq('c')
    end

    it 'selects the whole list when all_selected is set' do
      app = app_with({ 'kits' => %w[a b c] })
      app.params['kits', 'multi_selection'] = true
      app.params['kits', 'all_selected'] = true
      gate(app)

      expect(app.params['kits']).to eq('a,b,c')
    end

    it 'yields an empty string when nothing is pre-selected, as an untouched form does' do
      app = app_with({ 'kits' => %w[a b c] })
      app.params['kits', 'multi_selection'] = true
      gate(app)

      expect(app.params['kits']).to eq('')
    end

    it 'never leaves a multi_selection param as a Ruby Array literal' do
      app = app_with({ 'kits' => %w[a b c] })
      app.params['kits', 'multi_selection'] = true
      app.params['kits', 'selected'] = 'a'
      gate(app)

      expect(app.params['kits']).to be_a(String)
      expect(app.params['kits'].to_s).not_to include('[')
    end

    it 'reports every unsatisfied required param, not just the first' do
      app = app_with({ 'refBuild' => selector, 'other' => '' },
                     required: %w[refBuild other])
      ok, svc = gate(app)

      expect(ok).to be false
      expect(svc.errors.size).to eq(2)
    end

    it 'passes when the app declares no required params' do
      ok, = gate(app_with({ 'refBuild' => selector }))
      expect(ok).to be true
    end
  end
end
