require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Legacy's grandchild dataset — an EXTRA dataset a run produces one level below its output
# dataset — was never implemented in New SUSHI. Legacy builds it at SUBMIT time from the app's
# own Ruby (sushiApp.rb:656 hook), writes one grandchild_dataset.tsv into the result dir (:759),
# copies each of its [File] values un-batched in the job footer (:632-641), and persists it as a
# DataSet whose ParentID is the OUTPUT dataset (:935).
#
# The gap surfaced on 2026-08-13: ScSeurat needs a CountMatrix column that only a downstream-facing
# dataset carries, and there was no mechanism by which any app could hand one over — the rows were
# neither stored nor copied, which is also why the task #6 footer had nothing to copy.
#
# Of the 17 allow-listed apps only CellRangerMultiApp declares grandchild rows, and only for a
# MULTIPLEXED run, so the default path must stay completely inert.
RSpec.describe 'grandchild datasets' do
  let(:scratch) { Dir.mktmpdir('sushi-grandchild-spec') }
  let(:project) { create(:project, number: 35611) }
  let(:data_set) { create(:data_set, project: project) }

  before { allow(SushiConfigHelper).to receive(:scratch_dir).and_return(scratch) }
  after { FileUtils.remove_entry(scratch) if File.directory?(scratch) }

  # An app that declares two grandchild rows, shaped like CellRangerMulti's (per-sample
  # CountMatrix under the run directory).
  def app_with_grandchildren(rows)
    app = SushiFabric::SushiApp.new
    app.name = 'CellRangerMulti'
    app.dataset_sushi_id = data_set.id
    app.dataset = { 'Name' => 'tinygex' }
    app.define_singleton_method(:grandchild_datasets) { rows }
    app.define_singleton_method(:next_dataset) do
      { 'Name' => 'tinygex', 'ResultDir [File]' => File.join(result_dir, 'tinygex') }
    end
    app.prepare_result_dir
    app
  end

  let(:grandchild_rows) do
    [
      { 'Name' => 'sample1', 'CountMatrix [File]' => 'p35611/run/tinygex/s1/matrix',
        'Species' => 'Homo sapiens' },
      { 'Name' => 'sample2', 'CountMatrix [File]' => 'p35611/run/tinygex/s2/matrix',
        'Condition [Factor]' => 'ctrl' }
    ]
  end

  describe 'the default: no app declares them' do
    let(:plain) do
      app = SushiFabric::SushiApp.new
      app.name = 'STAR'
      app.dataset_sushi_id = data_set.id
      app.dataset = { 'Name' => 'mut11' }
      app.prepare_result_dir
      app
    end

    it 'declares none' do
      expect(plain.grandchild_datasets).to eq([])
    end

    it 'writes no tsv' do
      expect(plain.write_grandchild_dataset_tsv).to be_nil
      expect(File.exist?(File.join(plain.scratch_result_dir, 'grandchild_dataset.tsv'))).to be false
    end

    it 'adds nothing to the job script footer' do
      expect(plain.grandchild_copy_lines).to eq([])
    end
  end

  describe 'grandchild_dataset.tsv' do
    it 'holds every row under the UNION of their keys, as legacy does' do
      app = app_with_grandchildren(grandchild_rows)
      written = app.write_grandchild_dataset_tsv

      expect(written[:path]).to eq(File.join(app.scratch_result_dir, 'grandchild_dataset.tsv'))
      table = CSV.read(written[:path], col_sep: "\t")
      expect(table.first).to eq(['Name', 'CountMatrix [File]', 'Species', 'Condition [Factor]'])
      expect(table.length).to eq(3)
      # A key absent from a row is written blank, not shifted into the next column.
      expect(table[2]).to eq(['sample2', 'p35611/run/tinygex/s2/matrix', nil, 'ctrl'])
    end

    it 'lands in the result dir, which is the directory copied to gStore at submit' do
      app = app_with_grandchildren(grandchild_rows)
      app.write_grandchild_dataset_tsv
      expect(Dir.children(app.scratch_result_dir)).to include('grandchild_dataset.tsv')
    end
  end

  describe 'the job script footer' do
    it 'emits ONE un-batched copy per [File] value, as legacy does' do
      app = app_with_grandchildren(grandchild_rows)
      lines = app.grandchild_copy_lines

      expect(lines.length).to eq(2)
      expect(lines[0]).to include('matrix')
      # Un-batched: the two sources share no single command even though both are copies.
      expect(lines.none? { |line| line.scan('matrix').length > 1 }).to be true
    end

    it 'skips untagged and blank values' do
      app = app_with_grandchildren([{ 'Name' => 'sample1', 'CountMatrix [File]' => '',
                                      'Species' => 'Homo sapiens' }])
      expect(app.grandchild_copy_lines).to eq([])
    end

    it 'sits between the declared-output copies and the cleanup, as legacy orders it' do
      app = app_with_grandchildren(grandchild_rows)
      script = app.generate_job_script

      declared_copy = script.index(app.gstore_copy_lines.first)
      first_grandchild = script.index(app.grandchild_copy_lines.first)
      cleanup = script.index('rm -rf "$SCRATCH_DIR"')

      expect([declared_copy, first_grandchild, cleanup]).to all(be_truthy)
      expect(declared_copy).to be < first_grandchild
      expect(first_grandchild).to be < cleanup
    end
  end

  describe 'persistence through JobSubmissionService' do
    def service_for(app, output_dataset_id)
      svc = JobSubmissionService.new(dataset_id: data_set.id, app_name: 'CellRangerMulti',
                                     parameters: {}, user: nil)
      svc.instance_variable_set(:@sushi_app, app)
      svc.instance_variable_set(:@app_name, 'CellRangerMulti')
      svc.instance_variable_set(:@dataset_id, data_set.id)
      svc.instance_variable_set(:@input_dataset, data_set)
      svc.instance_variable_set(:@output_dataset_id, output_dataset_id)
      svc.instance_variable_set(:@errors, [])
      svc.instance_variable_set(:@grandchild_tsv, app.write_grandchild_dataset_tsv)
      svc
    end

    # Reuse the input dataset's user: the :user factory has no login sequence, so a second
    # created user trips the UNIQUE constraint on users.login.
    let(:output_dataset) do
      create(:data_set, project: project, user: data_set.user, name: 'CellRangerMulti_out')
    end

    it 'creates ONE dataset holding every grandchild row, parented to the OUTPUT dataset' do
      app = app_with_grandchildren(grandchild_rows)
      svc = service_for(app, output_dataset.id)

      expect(svc.send(:create_grandchild_datasets)).to be true
      created = DataSet.find(svc.instance_variable_get(:@grandchild_dataset_id))

      expect(created.parent_id).to eq(output_dataset.id) # belongs_to :data_set, foreign_key: :parent_id
      expect(created.samples.length).to eq(2)
      expect(created.comment).to eq('autogenerated grandchild')
      expect(created.child).to be true # legacy forces it when @grandchild is set, and it is by default
    end

    it 'names it from the first row when no grandchildName param was given' do
      app = app_with_grandchildren(grandchild_rows)
      svc = service_for(app, output_dataset.id)
      svc.send(:create_grandchild_datasets)

      expect(DataSet.find(svc.instance_variable_get(:@grandchild_dataset_id)).name).to eq('sample1')
    end

    it 'prefers an explicit grandchildName param, as legacy does' do
      app = app_with_grandchildren(grandchild_rows)
      app.params['grandchildName'] = 'multiplexed_samples'
      svc = service_for(app, output_dataset.id)
      svc.send(:create_grandchild_datasets)

      expect(DataSet.find(svc.instance_variable_get(:@grandchild_dataset_id)).name)
        .to eq('multiplexed_samples')
    end

    it 'falls back to <app>_grandchild_1 when no row carries a Name' do
      app = app_with_grandchildren([{ 'CountMatrix [File]' => 'p35611/run/x/matrix' }])
      svc = service_for(app, output_dataset.id)
      svc.send(:create_grandchild_datasets)

      expect(DataSet.find(svc.instance_variable_get(:@grandchild_dataset_id)).name)
        .to eq('CellRangerMulti_grandchild_1')
    end

    # Pin the call SITES in #submit: the tsv write (before the gStore copy, so it is included)
    # and the DB row (after the output dataset, so it can be its child). Everything the spec
    # cannot do for real — the gStore copy and the job rows — is stubbed; build_job_units,
    # create_output_dataset and create_grandchild_datasets all run.
    it 'is wired into #submit, parented to the output dataset it created' do
      rows = [{ 'Name' => 's1', 'Read1 [File]' => 'p35611/in/s1_R1.gz' }]
      app = SushiFabric::SushiApp.new
      app.name = 'CellRangerMulti'
      app.dataset_sushi_id = data_set.id
      app.dataset_hash = rows
      app.dataset = rows
      app.params['process_mode'] = 'DATASET'
      app.next_dataset_name = 'CellRangerMulti_out'
      app.define_singleton_method(:next_dataset) do
        { 'Name' => 's1', 'ResultDir [File]' => File.join(result_dir, 's1') }
      end
      app.define_singleton_method(:grandchild_datasets) do
        [{ 'Name' => 'demuxed', 'CountMatrix [File]' => File.join(result_dir, 's1', 'matrix') }]
      end

      svc = JobSubmissionService.new(dataset_id: data_set.id, app_name: 'CellRangerMulti',
                                     parameters: {}, user: nil)
      allow(svc).to receive(:validate_inputs) do
        svc.instance_variable_set(:@input_dataset, data_set)
        true
      end
      allow(svc).to receive(:load_sushi_app) do
        svc.instance_variable_set(:@sushi_app, app)
        true
      end
      allow(svc).to receive(:configure_sushi_app) { app.prepare_result_dir }
      allow(svc).to receive(:copy_scratch_to_gstore).and_return(true)
      allow(svc).to receive(:create_job_records).and_return(true)

      expect(svc.submit).to be true

      grandchild = DataSet.find_by(comment: 'autogenerated grandchild')
      expect(grandchild).not_to be_nil
      expect(grandchild.name).to eq('demuxed')
      expect(grandchild.parent_id).to eq(svc.output_dataset.id)
      # And the tsv was written before the copy step, i.e. it is in the directory that gets copied.
      expect(File.exist?(File.join(app.scratch_result_dir, 'grandchild_dataset.tsv'))).to be true
    end

    it 'does nothing at all when the app declared none' do
      app = app_with_grandchildren([])
      svc = service_for(app, output_dataset.id)

      expect { expect(svc.send(:create_grandchild_datasets)).to be true }
        .not_to change(DataSet, :count)
    end
  end

  # build_job_units has to populate result_dataset for grandchild_datasets to see which samples
  # were processed; legacy does it in sample_mode/dataset_mode (sushiApp.rb:890, :914). Without
  # it, CellRangerMultiApp falls back to @dataset, which after a fan-out is only the LAST sample.
  describe 'result_dataset feeds the grandchild hook' do
    it 'collects one row per job unit' do
      rows = [{ 'Name' => 's1', 'Read1 [File]' => 'a' }, { 'Name' => 's2', 'Read1 [File]' => 'b' }]
      app = SushiFabric::SushiApp.new
      app.name = 'CellRangerMulti'
      app.dataset_sushi_id = data_set.id
      app.dataset_hash = rows
      app.params['process_mode'] = 'SAMPLE'
      app.define_singleton_method(:next_dataset) { { 'Name' => dataset['Name'], 'Out [File]' => 'p/x' } }
      app.prepare_result_dir

      svc = JobSubmissionService.new(dataset_id: data_set.id, app_name: 'CellRangerMulti',
                                    parameters: {}, user: nil)
      svc.instance_variable_set(:@sushi_app, app)
      svc.instance_variable_set(:@app_name, 'CellRangerMulti')
      svc.instance_variable_set(:@dataset_id, data_set.id)
      svc.send(:build_job_units)

      expect(app.result_dataset.map { |row| row['Name'] }).to eq(%w[s1 s2])
    end
  end
end
