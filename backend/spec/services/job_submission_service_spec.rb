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

    it 'keeps a multi_selection param as a list instead of collapsing it' do
      app = app_with({ 'kits' => %w[a b c] }, required: ['kits'])
      app.params['kits', 'multi_selection'] = true
      ok, = gate(app)

      expect(ok).to be true
      expect(app.params['kits']).to eq(%w[a b c])
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
