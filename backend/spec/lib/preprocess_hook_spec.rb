require 'rails_helper'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Regression for the Level-2 finding of 2026-08-06 (CountQC against the legacy oracle
# p35611/o35755_CountQC_2025-08-21--10-06-00).
#
# Legacy calls the app's own #preprocess from SushiApp#run -> #test_run, between
# set_dir_paths and validation. The shim never defined the hook and the submit service
# never called it, so for the NINE allow-listed apps that implement it the body simply
# never ran:
#   - DESeq2 / EdgeR / CountQC / ScSeurat seed @random_string there; without it the
#     Live Report link degrades from ".../counts-xysrgtcxgabp-EzResult.RData" to
#     ".../counts--EzResult.RData" — the per-run token that keeps the shiny app's
#     result files distinct is simply absent;
#   - DESeq2 also renames @name to "<name>_<sampleGroup>--over--<refGroup>";
#   - FastqScreen / STAR / Kallisto / Bowtie2 / BWA add 'Read2' to @required_columns
#     for a paired run;
#   - Kallisto additionally appends 'fragment-length'/'sd' to @required_params and
#     auto-corrects a GPU request onto a GPU partition.
# Because it can append to @required_params, the hook has to run BEFORE the required-param
# gate, exactly as legacy orders it.
RSpec.describe 'SushiApp#preprocess hook' do
  it 'exists on the base class as a no-op, so every app responds to it' do
    app = SushiFabric::SushiApp.new
    expect(app).to respond_to(:preprocess)
    expect { app.preprocess }.not_to raise_error
  end

  it 'lets a subclass seed state that next_dataset then reads' do
    klass = Class.new(SushiFabric::SushiApp) do
      def initialize
        super
        @name = 'Demo'
      end

      def preprocess
        @random_string = 'abcdefghijkl'
      end

      def next_dataset
        { 'Name' => 'Demo', 'Live Report [Link]' => "http://x/?data=counts-#{@random_string}-EzResult.RData" }
      end
    end

    app = klass.new
    expect(app.next_dataset['Live Report [Link]']).to include('counts--EzResult')

    app.preprocess
    expect(app.next_dataset['Live Report [Link]']).to include('counts-abcdefghijkl-EzResult')
  end
end

RSpec.describe JobSubmissionService, 'preprocess ordering' do
  # A stand-in whose preprocess appends a required param. If the service ran the hook
  # after the gate (or not at all) the gate would pass and the omission would reach SLURM.
  let(:app) do
    Class.new(SushiFabric::SushiApp) do
      def initialize
        super
        @name = 'Demo'
        @params['fragment-length'] = ''
      end

      def preprocess
        @required_params << 'fragment-length'
      end
    end.new
  end

  it 'runs the hook before the required-param gate' do
    svc = described_class.new(dataset_id: 1, app_name: 'Demo', parameters: {}, user: 'u')
    svc.instance_variable_set(:@sushi_app, app)
    svc.instance_variable_set(:@normalized_app_name, 'Demo')

    app.preprocess # what submit does immediately after configure_sushi_app
    expect(svc.send(:resolve_and_validate_params)).to be false
    expect(svc.errors.join).to include('fragment-length')
  end
end
