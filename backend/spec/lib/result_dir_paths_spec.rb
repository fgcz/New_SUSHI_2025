require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Regression for the Level-2 finding of 2026-08-06 (first STAR run to reach SLURM
# COMPLETED on fgcz-h-083, diffed against the legacy oracle
# p35611/o35755_STAR_2026-05-15--09-01-48).
#
# Legacy SushiApp#set_dir_paths keeps TWO distinct paths:
#   @result_dir        = "p35611/<run>"                      PROJECT-RELATIVE
#   @gstore_result_dir = "/srv/gstore/projects/p35611/<run>"  ABSOLUTE
# The shim had collapsed them into one absolute path. @result_dir is what apps embed in
# their output dataset [File]/[Link] values and what is emitted as param[['resultDir']],
# and the gStore web layer builds URLs as "https://fgcz-gstore.uzh.ch/projects/" + it.
# The collapse therefore produced dead links of the form
#   https://fgcz-gstore.uzh.ch/projects//srv/gstore/projects/p35611/...
# (observed verbatim in the run's mut11-igv.html) and dataset rows whose File paths a
# downstream app cannot resolve against dataRoot.
RSpec.describe 'SushiApp result-directory path contract' do
  let(:project)  { create(:project, number: 35611) }
  let(:data_set) { create(:data_set, project: project) }
  let(:scratch)  { Dir.mktmpdir('sushi-result-dir-spec') }
  let(:app)      { SushiFabric::SushiApp.new }

  before do
    allow(SushiConfigHelper).to receive(:scratch_dir).and_return(scratch)
    app.name = 'STAR'
    app.dataset_sushi_id = data_set.id
    app.dataset = { 'Name' => 'mut11', 'Read1' => 'p35611/ventricles_100k/MutantSample_1_R1.fastq.gz' }
    app.prepare_result_dir
  end

  after { FileUtils.remove_entry(scratch) if File.directory?(scratch) }

  it 'makes result_dir project-relative, not an absolute filesystem path' do
    expect(app.result_dir).to eq(File.join('p35611', app.result_dir_base))
    expect(app.result_dir).not_to start_with('/')
    expect(app.result_dir).not_to start_with(app.gstore_dir)
  end

  it 'makes gstore_result_dir the absolute path, = gstore_dir + result_dir' do
    expect(app.gstore_result_dir).to eq(File.join(app.gstore_dir, app.result_dir))
    expect(app.gstore_result_dir).to start_with('/')
    expect(app.gstore_script_dir).to eq(File.join(app.gstore_result_dir, 'scripts'))
    expect(app.gstore_project_dir).to eq(File.join(app.gstore_dir, 'p35611'))
  end

  it 'builds a gStore URL with no doubled path segment' do
    url = "https://fgcz-gstore.uzh.ch/projects/#{app.result_dir}/mut11.bam"
    expect(url).not_to include('projects//srv')
    expect(url).to eq("https://fgcz-gstore.uzh.ch/projects/p35611/#{app.result_dir_base}/mut11.bam")
  end

  it 'keeps the scratch paths absolute and separate from gstore' do
    expect(app.scratch_result_dir).to eq(File.join(scratch, app.result_dir_base))
    expect(app.job_script_dir).to eq(File.join(app.scratch_result_dir, 'scripts'))
  end

  it 'falls back to the "results" project directory when the dataset has no project' do
    orphan = SushiFabric::SushiApp.new
    orphan.name = 'STAR'
    orphan.prepare_result_dir
    expect(orphan.result_dir).to start_with('results/')
    expect(orphan.gstore_result_dir).to eq(File.join(orphan.gstore_dir, orphan.result_dir))
  end

  describe 'param[["resultDir"]] emitted into the job script' do
    it 'is the project-relative path, as legacy emits it' do
      script = app.run_RApp('EzAppSTAR')
      expect(script).to include("param[['resultDir']] = '#{app.result_dir}'")
      expect(script).to include("param[['dataRoot']] = '#{app.gstore_dir}'")
      expect(script).not_to include("param[['resultDir']] = '/srv")
    end
  end
end

# Regression for the same Level-2 diff: `@last_job || true` collapsed a legitimate false
# to true, so EVERY script of a SAMPLE fan-out declared itself the last job. Legacy emits
# @last_job verbatim (FALSE on every sample but the final one), and the flag gates
# end-of-run finalization in ezRun.
RSpec.describe 'isLastJob reflects last_job verbatim' do
  let(:app) { SushiFabric::SushiApp.new }

  before do
    app.name = 'STAR'
    app.dataset = { 'Name' => 'mut11' }
  end

  it 'emits FALSE for a non-final sample of a fan-out' do
    app.last_job = false
    expect(app.run_RApp('EzAppSTAR')).to include("param[['isLastJob']] = FALSE")
  end

  it 'emits TRUE for the final sample' do
    app.last_job = true
    expect(app.run_RApp('EzAppSTAR')).to include("param[['isLastJob']] = TRUE")
  end

  it 'guards conda activate with set +e so it cannot abort a `set -e` script' do
    script = app.run_RApp('EzAppSTAR', conda_env: 'some_env')
    expect(script).to include('set +e; conda activate some_env; set -e')
  end
end
