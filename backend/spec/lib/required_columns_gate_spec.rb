require 'rails_helper'
require Rails.root.join('lib', 'sushi_fabric').to_s

# The API submit path had NO dataset-shape check at all, while legacy enforces @required_columns
# twice: in SushiApp#test_run before a script is written, and in the UI, where an app whose
# required columns the dataset does not satisfy is never offered
# (SushiApplication#required_columns_satisfied_by?).
#
# Consequence, measured on fgcz-h-083 on 2026-08-13: Fastqc10x and FastqScreen10x were submitted
# against a dataset whose RawDataDir was a directory of FASTQs. Both were accepted with 201, got
# an output dataset row and a gStore result directory, were sbatched, and died 16 s in with
#   all(grepl("\\.tar$", sampleDirs)) is not TRUE
# leaving an empty result dir behind. The column check cannot express "must be a tar", so it
# would not have caught that exact case — but a missing column, the same class of error, now
# fails in one second with the column named.
RSpec.describe 'required_columns gate' do
  def app_with(required, rows)
    app = SushiFabric::SushiApp.new
    app.name = 'TestApp'
    app.required_columns = required
    app.dataset_hash = rows
    app
  end

  # Tagged keys, as they come out of DataSet#samples.
  let(:bam_rows) do
    [{ 'Name' => 'mut11', 'BAM [File]' => 'p1/x/mut11.bam', 'BAI [File]' => 'p1/x/mut11.bam.bai',
       'refBuild' => 'Some/Build', 'Species' => 'Mus musculus' }]
  end

  describe 'AND mode (a flat list: every column required)' do
    it 'is satisfied when every required column is present, tags stripped' do
      app = app_with(%w[Name BAM BAI refBuild Species], bam_rows)
      expect(app.check_required_columns).to be true
      expect(app.required_columns_report[:mode]).to eq(:all)
    end

    it 'names exactly the missing columns' do
      app = app_with(['Name', 'BAM', 'BAI', 'refBuild', 'Species', 'Read Count'], bam_rows)
      report = app.required_columns_report
      expect(report[:satisfied]).to be false
      expect(report[:missing]).to eq(['Read Count'])
    end

    it 'accepts an app that requires nothing' do
      expect(app_with([], bam_rows).check_required_columns).to be true
    end

    it 'unions the columns of ALL rows, as legacy does' do
      rows = [{ 'Name' => 'a' }, { 'Name' => 'b', 'BAM [File]' => 'p1/x/b.bam' }]
      expect(app_with(%w[Name BAM], rows).check_required_columns).to be true
    end

    it 'is not satisfied by an empty dataset' do
      expect(app_with(%w[Name BAM], []).check_required_columns).to be false
    end
  end

  # CellRangerMultiApp is the only allow-listed app using this shape.
  describe 'ALTERNATIVES mode (a list of lists)' do
    let(:alternatives) do
      [%w[Name RawDataDir Species], ['Name', 'Read1', 'Read2', 'Species']]
    end

    it 'is satisfied by the tar/RawDataDir alternative' do
      rows = [{ 'Name' => 'tinygex', 'RawDataDir [File]' => 'p1/x/tinygex.tar', 'Species' => 'Homo sapiens' }]
      expect(app_with(alternatives, rows).check_required_columns).to be true
    end

    it 'is satisfied by the FASTQ alternative' do
      rows = [{ 'Name' => 'tinygex', 'Read1 [File]' => 'p1/x/r1.gz', 'Read2 [File]' => 'p1/x/r2.gz',
                'Species' => 'Homo sapiens' }]
      expect(app_with(alternatives, rows).check_required_columns).to be true
    end

    # DELIBERATE DEVIATION from legacy, and the reason it is deliberate: legacy asks
    # `satisfied_options == 1` (sushiApp.rb:341-347), so a dataset carrying BOTH alternatives is
    # rejected. ds 819 on 083 is exactly that dataset — RawDataDir *and* Read1/Read2 — and its
    # CellRangerMulti run completed correctly, because ezRun resolves the ambiguity itself and
    # prefers Read1 (app-cellRangerMulti.R:201-208). This gate exists to catch MISSING columns;
    # a superset is not a missing column.
    it 'accepts a dataset that satisfies BOTH alternatives, where legacy demands exactly one' do
      rows = [{ 'Name' => 'tinygex', 'RawDataDir [File]' => 'p1/x/tinygex', 'Read1 [File]' => 'p1/x/r1.gz',
                'Read2 [File]' => 'p1/x/r2.gz', 'Species' => 'Homo sapiens' }]
      report = app_with(alternatives, rows).required_columns_report
      expect(report[:satisfied]).to be true
      expect(report[:satisfied_options].length).to eq(2)
    end

    it 'is not satisfied when a partial mix leaves every alternative incomplete' do
      rows = [{ 'Name' => 'tinygex', 'Read1 [File]' => 'p1/x/r1.gz', 'Species' => 'Homo sapiens' }]
      report = app_with(alternatives, rows).required_columns_report
      expect(report[:satisfied]).to be false
      expect(report[:mode]).to eq(:alternatives)
      expect(report[:options].length).to eq(2)
    end
  end
end

# The gate as the submit path applies it: rejected before any side effect, with the missing
# column named, and AFTER preprocess — which is where an app appends to @required_columns.
RSpec.describe 'JobSubmissionService required-columns rejection' do
  let(:project)  { create(:project, number: 35611) }
  let(:data_set) { create(:data_set, project: project) }

  def service_with(app)
    svc = JobSubmissionService.new(dataset_id: data_set.id, app_name: 'TestApp',
                                   parameters: {}, user: 'tester')
    svc.instance_variable_set(:@sushi_app, app)
    svc.instance_variable_set(:@app_name, 'TestApp')
    svc.instance_variable_set(:@dataset_id, data_set.id)
    svc.instance_variable_set(:@errors, [])
    svc
  end

  def app_with(required, rows)
    app = SushiFabric::SushiApp.new
    app.name = 'TestApp'
    app.required_columns = required
    app.dataset_hash = rows
    app
  end

  it 'reports the missing column and the columns the dataset does have' do
    app = app_with(%w[Name RawDataDir], [{ 'Name' => 'a', 'Read1 [File]' => 'p1/x/r1.gz' }])
    svc = service_with(app)

    expect(svc.send(:validate_required_columns)).to be false
    message = svc.instance_variable_get(:@errors).first
    expect(message).to include('needs column(s) RawDataDir')
    expect(message).to include('Read1')
  end

  it 'lists both column sets when the app declares alternatives' do
    app = app_with([%w[Name RawDataDir], %w[Name Read1 Read2]], [{ 'Name' => 'a' }])
    svc = service_with(app)

    expect(svc.send(:validate_required_columns)).to be false
    expect(svc.instance_variable_get(:@errors).first)
      .to include('[Name, RawDataDir] or [Name, Read1, Read2]')
  end

  it 'passes a dataset that satisfies the app' do
    app = app_with(%w[Name Read1], [{ 'Name' => 'a', 'Read1 [File]' => 'p1/x/r1.gz' }])
    expect(service_with(app).send(:validate_required_columns)).to be true
  end

  # The gate is worthless if nothing calls it: pin the call SITE inside #submit, and that it
  # aborts before any side effect (no job units, no output dataset, no DB rows).
  #
  # Everything downstream that would touch the outside world is stubbed even though a working
  # gate never reaches it. That is the point: an example which is only harmless while the code
  # is CORRECT is a trap for the next mutation run. Without these stubs, neutering the gate sent
  # this example into the real copy_scratch_to_gstore, where `g-req -w` sat waiting for a
  # transfer daemon — 10 minutes per mutation instead of 15 seconds.
  it 'is applied by #submit, which stops before creating anything' do
    app = app_with(%w[Name RawDataDir], [{ 'Name' => 'a', 'Read1 [File]' => 'p1/x/r1.gz' }])
    app.job_script_dir = Dir.mktmpdir('sushi-required-columns-gate')
    svc = JobSubmissionService.new(dataset_id: data_set.id, app_name: 'TestApp',
                                   parameters: {}, user: 'tester')
    allow(svc).to receive(:validate_inputs) do
      svc.instance_variable_set(:@input_dataset, data_set)
      true
    end
    allow(svc).to receive(:load_sushi_app) do
      svc.instance_variable_set(:@sushi_app, app)
      true
    end
    allow(svc).to receive(:configure_sushi_app)
    allow(svc).to receive(:copy_scratch_to_gstore).and_return(true)
    allow(svc).to receive(:create_job_records).and_return(true)

    # The ABORT is the claim, so assert on it directly. Asserting only "returns false and wrote
    # nothing" passed even with the `return false unless` removed from #submit, because the run
    # then died a few steps later for an unrelated reason (build_job_units raising on a bare
    # app) — a mutation that survives because the test measures the symptom, not the cause.
    expect(svc).not_to receive(:build_job_units)

    expect { expect(svc.submit).to be false }.not_to change(DataSet, :count)
    expect(svc.errors.first).to include('needs column(s) RawDataDir')
    expect(svc.output_dataset).to be_nil
    expect(svc.jobs).to be_nil
  ensure
    FileUtils.remove_entry(app.job_script_dir) if app&.job_script_dir&.start_with?(Dir.tmpdir)
  end

  # Legacy's FastqcApp#preprocess appends 'Read2' for a paired run, so a gate running before
  # preprocess would accept a single-end dataset for a paired submission.
  it 'sees columns an app appends to required_columns in preprocess' do
    app = app_with(%w[Name Read1], [{ 'Name' => 'a', 'Read1 [File]' => 'p1/x/r1.gz' }])
    def app.preprocess
      @required_columns += ['Read2']
    end
    app.preprocess

    svc = service_with(app)
    expect(svc.send(:validate_required_columns)).to be false
    expect(svc.instance_variable_get(:@errors).first).to include('Read2')
  end
end
