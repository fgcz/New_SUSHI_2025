require 'rails_helper'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Regression for the Level-2 finding of 2026-08-06 (Kallisto against the legacy oracle
# p35611/o35755_Kallisto_2024-07-24--14-28-11).
#
# find_module_version was a stub returning the module name unchanged, so job scripts said
# "module add Aligner/kallisto" while legacy said "module add Aligner/kallisto/0.46.1".
# An unversioned module loads whatever the cluster currently defaults to, so the SAME job
# silently returns different numbers as the cluster moves: the Level-2 run reproduced the
# oracle's inputs and parameters exactly yet produced different eff_length/tpm, purely
# because the default had moved 0.46.1 -> 0.51.1. Pinning does not make old runs
# reproducible retroactively — it records what a run actually used so it can be repeated.
#
# Port of legacy SushiApp#check_latest_modules_version + the module_add_commands branch of
# #job_header.
RSpec.describe 'SushiApp module version pinning' do
  let(:app) do
    Class.new(SushiFabric::SushiApp) do
      def initialize
        super
        @name = 'Kallisto'
        @modules = ['Aligner/kallisto', 'Tools/samtools', 'QC/fastp', 'Dev/R']
        @dataset = { 'Name' => 'mut11' } # run_RApp renders the input block from it
      end
    end.new
  end

  # Real shape of `module whatis ... | cut -f1 -d' ' | uniq`: the login profile prints
  # unrelated banner lines and blanks between entries.
  let(:whatis_output) do
    <<~OUT
      Agent

      Aligner/kallisto/0.51.1

      Tools/samtools/1.20

      QC/fastp/0.23.4

      Dev/R/4.6.0
    OUT
  end

  before { allow(app).to receive(:module_whatis_output).and_return(whatis_output) }

  it 'resolves every requested module to its concrete version' do
    expect(app.resolve_module_versions).to eq(
      ['Aligner/kallisto/0.51.1', 'Tools/samtools/1.20', 'QC/fastp/0.23.4', 'Dev/R/4.6.0']
    )
  end

  it 'drops banner lines and blanks that are not requested modules' do
    expect(app.resolve_module_versions).not_to include('Agent')
    expect(app.resolve_module_versions).to all(be_present)
  end

  it 'queries lmod only once even though a fan-out generates many scripts' do
    3.times { app.resolve_module_versions }
    expect(app).to have_received(:module_whatis_output).once
  end

  it 'writes the pinned versions into the job script' do
    script = app.generate_job_script
    expect(script).to include('source /usr/local/ngseq/etc/lmod_profile')
    expect(script).to include('module add Aligner/kallisto/0.51.1 Tools/samtools/1.20 QC/fastp/0.23.4 Dev/R/4.6.0')
    expect(script).not_to match(/^module add Aligner\/kallisto\s/)
  end

  context 'when lmod cannot resolve every module' do
    let(:whatis_output) { "Aligner/kallisto/0.51.1\nTools/samtools/1.20\n" }

    # Legacy emits NO module add line rather than a half-resolved one, so the job fails
    # loudly on a missing tool instead of quietly running against the wrong ones.
    it 'omits the module add line entirely' do
      expect(app.generate_job_script).not_to include('module add')
    end

    it 'still sources the profile' do
      expect(app.generate_job_script).to include('source /usr/local/ngseq/etc/lmod_profile')
    end
  end

  context 'with no module source configured' do
    before { allow(app).to receive(:module_source).and_return('') }

    it 'emits neither source nor module add' do
      script = app.generate_job_script
      expect(script).not_to include('module add')
      expect(script).not_to include('source ')
    end
  end
end
