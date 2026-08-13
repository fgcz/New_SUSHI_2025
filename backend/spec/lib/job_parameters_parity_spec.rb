require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib', 'sushi_fabric').to_s

# `data_sets.job_parameters` must record what the run actually USED, not what the caller
# happened to pass. Legacy builds `@output_params` = the app's fully-resolved parameter set
# plus the app class name (sushiApp.rb:354-356) and persists exactly that on the output
# dataset (sushiApp.rb:931 `next_dataset.job_parameters = @output_params`).
#
# The legacy oracle, read off a real legacy run on fgcz-h-083 (dataset 801, produced by
# rdomi's CountQC job 736), stores all of:
#
#   cores, ram, scratch, partition, process_mode, samples, name, refBuild, refFeatureFile,
#   featureLevel, normMethod, runGO, backgroundExpression, topGeneSize, selectByFtest,
#   transcriptTypes, specialOptions, expressionName, mail, sushi_app: CountQCApp
#
# New SUSHI was storing `@parameters` -- only the caller's API arguments. A Fastqc submit
# that passed four params recorded exactly those four (dataset 833, 51 bytes), so the
# reproducibility record legacy provides was missing: no resolved defaults, no
# process_mode/partition, and no `sushi_app` at all.
#
# Note this is NOT the same thing as `param[['sushi_app']]` in the job script: legacy's
# run_RApp iterates @params, which never contains the key, so neither system emits it there
# and neither should. `parameters.tsv` already had parity (JobSubmissionService writes
# `sushi_app` explicitly); `job_parameters` is where the gap actually was.
RSpec.describe 'job_parameters parity with legacy' do
  let(:project) { create(:project, number: 35611) }
  let(:input_dataset) { create(:data_set, project: project) }
  let(:scratch) { Dir.mktmpdir('sushi-job-params-spec') }

  before { allow(SushiConfigHelper).to receive(:scratch_dir).and_return(scratch) }
  after { FileUtils.remove_entry(scratch) if File.directory?(scratch) }

  let(:app_class) do
    cfg = Rails.application.config
    old_dir = cfg.legacy_apps_dir
    old_list = cfg.legacy_apps_allowlist
    cfg.legacy_apps_dir = Rails.root.join('spec', 'fixtures', 'legacy_apps').to_s
    cfg.legacy_apps_allowlist = ['FooBar']
    LegacyAppLoader.load('FooBar')
  ensure
    cfg.legacy_apps_dir = old_dir
    cfg.legacy_apps_allowlist = old_list
  end

  let(:app) do
    a = app_class.new
    a.dataset_sushi_id = input_dataset.id
    a.dataset = { 'Name' => 'tinygex' }
    a.prepare_result_dir
    a
  end

  # The caller passes ONE parameter. Everything else in the record has to come from the
  # app's own resolved params, which is the whole point.
  def submit_with(caller_params)
    svc = JobSubmissionService.new(dataset_id: input_dataset.id, app_name: 'FooBar',
                                   parameters: caller_params, user: nil)
    svc.instance_variable_set(:@sushi_app, app)
    svc.instance_variable_set(:@app_name, 'FooBar')
    svc.instance_variable_set(:@dataset_id, input_dataset.id)
    svc.instance_variable_set(:@input_dataset, input_dataset)
    svc.instance_variable_set(:@parameters, caller_params)
    svc.instance_variable_set(:@errors, [])
    # The real submit path applies the caller's arguments onto the app here; without it the
    # spec would be asserting against the app's untouched defaults and could not tell
    # "recorded the resolved params" apart from "recorded nothing the caller sent".
    svc.send(:configure_sushi_app)
    expect(svc.send(:create_output_dataset, [{ 'Name' => 'out1' }])).to be_truthy
    DataSet.find(svc.instance_variable_get(:@output_dataset_id)).job_parameters
  end

  it 'records the app class name under sushi_app, as legacy does' do
    expect(submit_with({})['sushi_app']).to eq('FooBarApp')
  end

  it "records the app's resolved defaults, not just the caller's arguments" do
    recorded = submit_with('cores' => 4)

    # FooBarApp declares process_mode and partition; the caller passed neither.
    expect(recorded).to include('process_mode' => 'DATASET')
    expect(recorded).to have_key('partition')
    # And the caller's own argument is still there, resolved onto the app.
    expect(recorded['cores'].to_s).to eq('4')
  end

  it 'is strictly richer than the caller payload (the regression that motivated this)' do
    caller_params = { 'cores' => 4 }
    recorded = submit_with(caller_params)

    expect(recorded.keys).to include(*caller_params.keys)
    expect(recorded.keys.length).to be > caller_params.keys.length
    expect(recorded.keys).not_to match_array(caller_params.keys)
  end
end
