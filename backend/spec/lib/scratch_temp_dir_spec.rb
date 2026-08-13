require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Regression for the Level-2 finding of 2026-08-13: the first runs of RnaBamStats, DnaBamStats
# and Mpileup on fgcz-h-083 (jobs 760/761/762) all died on line 8 of their own job scripts.
#
# Their @name values are 'RNA BamStats', 'DNA BamStats' and 'samtools mpileup' — the only
# three of the 17 allow-listed legacy apps with a space in @name, which is exactly why the
# fourteen apps run before this never exposed it. The shim emitted the app name into the
# script unquoted, so
#
#   SCRATCH_DIR=/scratch/rna bamstats_2026-08-13--09-05-03_temp$$
#
# is not an assignment at all: bash reads it as `SCRATCH_DIR=/scratch/rna` prefixed to the
# command `bamstats_..._temp$$`. Verbatim from job 760's error log:
#
#   + SCRATCH_DIR=/scratch/rna
#   + bamstats_2026-08-13--09-05-03_temp582741
#   line 8: bamstats_2026-08-13--09-05-03_temp582741: command not found
#
# Legacy has no such bug because set_dir_paths (sushiApp.rb:507) runs
# @name.gsub!(/\s/,'_') BEFORE deriving any path from the name.
#
# The failure was loud, but the same split is silent and destructive in the footer, where the
# old code emitted a BARE relative name: `rm -rf samtools mpileup_..._temp$$` with cwd
# /scratch is a two-argument rm -rf, the first of which is an unrelated /scratch/samtools.
RSpec.describe 'scratch temp dir naming' do
  let(:scratch) { Dir.mktmpdir('sushi-scratch-temp-dir-spec') }
  let(:project) { create(:project, number: 35611) }
  let(:data_set) { create(:data_set, project: project) }

  before { allow(SushiConfigHelper).to receive(:scratch_dir).and_return(scratch) }
  after { FileUtils.remove_entry(scratch) if File.directory?(scratch) }

  def app_named(name, dataset: { 'Name' => 'mut11' })
    app = SushiFabric::SushiApp.new
    app.name = name
    app.dataset_sushi_id = data_set.id
    app.dataset = dataset
    app
  end

  describe 'legacy name sanitization (sushiApp.rb:507)' do
    it 'replaces whitespace in the app name with an underscore' do
      app = app_named('samtools mpileup')
      app.prepare_result_dir
      expect(app.name).to eq('samtools_mpileup')
    end

    it 'is idempotent, so the shim and the submission service can both call it' do
      app = app_named('RNA BamStats')
      3.times { app.normalize_name! }
      expect(app.name).to eq('RNA_BamStats')
    end

    it 'keeps a space out of the result dir when no next_dataset_name was given' do
      app = app_named('DNA BamStats')
      app.prepare_result_dir
      # This path is param[['resultDir']] and the prefix of every output [File] value.
      expect(app.result_dir).not_to match(/\s/)
      expect(app.result_dir).to start_with('p35611/DNA_BamStats_')
      expect(app.gstore_result_dir).not_to match(/\s/)
    end

    it 'leaves a name that needs no sanitizing untouched' do
      app = app_named('FeatureCounts')
      app.prepare_result_dir
      expect(app.name).to eq('FeatureCounts')
    end
  end

  describe 'the emitted script' do
    it 'assigns SCRATCH_DIR as ONE word for an app whose name has a space' do
      app = app_named('samtools mpileup')
      app.prepare_result_dir
      assignment = app.generate_job_script.lines.grep(/^SCRATCH_DIR=/).first.chomp

      expect(assignment).to match(/\ASCRATCH_DIR=\S+\z/)
      expect(assignment).to include('samtools_mpileup')
      expect(assignment).not_to include('samtools mpileup')
    end

    it 'never leaves a bare relative path in the rm -rf, whatever the names are' do
      app = app_named('samtools mpileup', dataset: { 'Name' => 'sample with spaces' })
      app.prepare_result_dir
      script = app.generate_job_script

      # The value, not a re-derived literal: one word after expansion, always.
      expect(script).to include('rm -rf "$SCRATCH_DIR" || exit 1')
      expect(script).not_to match(/^rm -rf (?!")/)
      expect(script).to include('mkdir "$SCRATCH_DIR" || exit 1')
      expect(script).to include('cd "$SCRATCH_DIR" || exit 1')
    end

    it 'cds back to the scratch root before removing the temp dir, as legacy does' do
      app = app_named('STAR')
      app.prepare_result_dir
      script = app.generate_job_script
      expect(script.index("cd #{scratch}\n")).to be < script.index('rm -rf "$SCRATCH_DIR"')
    end
  end

  describe 'legacy scratch dir composition (sushiApp.rb:548-552)' do
    it 'is the run result_dir_base plus the sample name plus _temp$$ in SAMPLE mode' do
      app = app_named('STAR')
      app.prepare_result_dir
      expect(app.scratch_temp_dir_name).to eq("#{app.result_dir_base}_mut11_temp$$")
    end

    it 'omits the sample name in DATASET mode, where dataset is the full array' do
      app = app_named('samtools mpileup', dataset: [{ 'Name' => 'mut11' }, { 'Name' => 'mut22' }])
      app.prepare_result_dir
      expect(app.scratch_temp_dir_name).to eq("#{app.result_dir_base}_temp$$")
    end

    it 'ties the temp dir to the result dir instead of taking a second timestamp' do
      app = app_named('STAR')
      app.prepare_result_dir
      # The old form was "#{@name.downcase}_#{Time.now}_temp$$": a different timestamp than
      # the run it belonged to, and lowercased.
      expect(app.scratch_temp_dir_name).to start_with(app.result_dir_base)
      expect(app.scratch_temp_dir_name).not_to start_with('star_')
    end

    it 'still produces a usable name when no result dir was prepared' do
      app = app_named('RNA BamStats')
      app.normalize_name!
      expect(app.scratch_temp_dir_name).to match(/\ARNA_BamStats_#{data_set.id}_.+_mut11_temp\$\$\z/)
    end
  end

  # The submission service derives the DEFAULT output-dataset name one line before
  # prepare_result_dir gets to sanitize @name, and that name becomes the gStore result
  # directory. This is the path every API submission that omits next_dataset_name takes —
  # i.e. the whole UI-less MCP path — so it needs its own net: with the service's
  # normalize_name! call removed, everything above still passes.
  describe 'JobSubmissionService default output name (the API path)' do
    let(:service) do
      svc = JobSubmissionService.new(dataset_id: data_set.id, app_name: 'Mpileup',
                                     parameters: {}, user: 'tester')
      svc.instance_variable_set(:@sushi_app, app_named('samtools mpileup'))
      svc.instance_variable_set(:@dataset_id, data_set.id)
      svc.instance_variable_set(:@input_dataset, data_set)
      svc.instance_variable_set(:@next_dataset_name, nil)
      svc
    end

    it 'never derives a result dir containing a space from the app name' do
      service.send(:configure_sushi_app)
      app = service.instance_variable_get(:@sushi_app)

      expect(app.next_dataset_name).to eq("samtools_mpileup_#{data_set.id}")
      expect(app.result_dir).not_to match(/\s/)
      expect(app.gstore_result_dir).not_to match(/\s/)

      # build_job_units assigns the row before generating; set_input_dataset has just reset
      # @dataset to the full array, and run_RApp renders its input block from a row.
      app.dataset = { 'Name' => 'mut11' }
      expect(app.generate_job_script.lines.grep(/^SCRATCH_DIR=/).first.chomp)
        .to match(/\ASCRATCH_DIR=\S+\z/)
    end

    it 'leaves an explicitly supplied next_dataset_name alone' do
      service.instance_variable_set(:@next_dataset_name, 'RnaBamStats_808_level2')
      service.send(:configure_sushi_app)
      app = service.instance_variable_get(:@sushi_app)

      expect(app.next_dataset_name).to eq('RnaBamStats_808_level2')
    end
  end
end
