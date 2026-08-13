require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib', 'sushi_fabric').to_s

# data_sets.sushi_app_name must hold the app's CLASS name, exactly as legacy writes it:
#
#   legacy sushiApp.rb:1039 -> sushi_app_name: self.class.name    # => "CellRangerApp"
#
# New SUSHI was persisting the raw API argument instead, which is the SHORT name the REST
# API and LegacyAppLoader use ("CellRanger"). Both spellings therefore accumulated for the
# same app -- on 083 legacy had written KallistoApp/CountQCApp/FastqcApp rows while New
# SUSHI wrote Kallisto/CountQC/Fastqc rows.
#
# Why it matters, and why it must be closed BEFORE the 082 write cutover: nothing inside
# this backend looks the value up (the API and frontend only display it), but two legacy
# consumers do compare it --
#
#   1. legacy's dataset filter matches `data_set.sushi_app_name =~ /<app>/i`
#      (data_set_controller.rb), so a row written as "CellRanger" does NOT match a filter
#      for "CellRangerApp" and New-SUSHI-produced datasets go INVISIBLE in the legacy UI.
#   2. B-Fabric registration passes `--sushi-app #{sushi_app_name}` (data_set.rb), so the
#      registered app identity would disagree with legacy's for the same analysis.
#
# The assertions below pin the class name, and pin that it is NOT the short API argument --
# asserting only `eq('FooBarApp')` would still pass if someone made the API require the
# long name instead of fixing the write.
RSpec.describe 'sushi_app_name parity with legacy' do
  let(:project) { create(:project, number: 35611) }
  let(:input_dataset) { create(:data_set, project: project) }
  let(:scratch) { Dir.mktmpdir('sushi-app-name-parity-spec') }

  before { allow(SushiConfigHelper).to receive(:scratch_dir).and_return(scratch) }
  after { FileUtils.remove_entry(scratch) if File.directory?(scratch) }

  # A real loaded app class, so `.class.name` means something: LegacyAppLoader resolves the
  # FooBar fixture to class FooBarApp while the API argument stays the short "FooBar".
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

  # Drive the persistence step directly: the surrounding submit path shells out to SLURM.
  def service_writing_output(app, short_app_name)
    svc = JobSubmissionService.new(dataset_id: input_dataset.id, app_name: short_app_name,
                                   parameters: {}, user: nil)
    svc.instance_variable_set(:@sushi_app, app)
    svc.instance_variable_set(:@app_name, short_app_name)
    svc.instance_variable_set(:@dataset_id, input_dataset.id)
    svc.instance_variable_set(:@input_dataset, input_dataset)
    svc.instance_variable_set(:@errors, [])
    svc
  end

  let(:app) do
    a = app_class.new
    a.dataset_sushi_id = input_dataset.id
    a.dataset = { 'Name' => 'tinygex' }
    a
  end

  describe 'the output dataset' do
    it 'records the app CLASS name, not the short API argument' do
      svc = service_writing_output(app, 'FooBar')

      expect(svc.send(:create_output_dataset, [{ 'Name' => 'out1' }])).to be_truthy

      written = DataSet.find(svc.instance_variable_get(:@output_dataset_id))
      expect(written.sushi_app_name).to eq('FooBarApp')     # == legacy's self.class.name
      expect(written.sushi_app_name).not_to eq('FooBar')    # the short REST/loader name
      expect(written.sushi_app_name).to eq(app.class.name)  # the legacy oracle itself
    end
  end

  describe 'the grandchild dataset' do
    let(:grandchild_rows) do
      [{ 'Name' => 'sample1', 'CountMatrix [File]' => 'p35611/run/s1/matrix' }]
    end

    it 'records the same class name as the output dataset' do
      rows = grandchild_rows
      app.define_singleton_method(:grandchild_datasets) { rows }
      app.define_singleton_method(:next_dataset) { { 'Name' => 'tinygex' } }
      app.prepare_result_dir

      svc = service_writing_output(app, 'FooBar')
      expect(svc.send(:create_output_dataset, [{ 'Name' => 'out1' }])).to be_truthy
      output_id = svc.instance_variable_get(:@output_dataset_id)

      # Must be a REAL tsv: create_grandchild_datasets short-circuits on a nil @grandchild_tsv
      # and would then return true having written nothing, so the assertions below would be
      # measuring an unwritten row.
      svc.instance_variable_set(:@grandchild_tsv, app.write_grandchild_dataset_tsv)
      expect(svc.send(:create_grandchild_datasets)).to be true
      expect(svc.instance_variable_get(:@grandchild_dataset_id)).to be_present

      grandchild = DataSet.find(svc.instance_variable_get(:@grandchild_dataset_id))
      expect(grandchild.parent_id).to eq(output_id)
      expect(grandchild.sushi_app_name).to eq('FooBarApp')
      expect(grandchild.sushi_app_name).not_to eq('FooBar')
    end
  end
end
