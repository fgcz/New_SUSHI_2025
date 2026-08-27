require 'rails_helper'

# The submit-time scratch -> gStore copy, which had no coverage at all: every other spec stubs
# `copy_scratch_to_gstore` out, and that is exactly how it shipped a command only a trxcopy
# process could run plus an unbounded `system()` call.
#
# What went wrong in production (082, 2026-08-21, the first write-authority submit): the command
# was `g-req copynow`, whose gtools implementation shells out to `ssh trxcopy@<file server>`.
# New SUSHI runs as masaomi, whose key authorised for trxcopy is passphrase-protected and not a
# default identity name, so ssh can only offer it via an ssh-agent. With no agent inherited, the
# ssh fell back to a password prompt whose output goes to /dev/null and waited forever — a Rails
# thread held for 30 minutes with NOTHING in the log. On 083 the same code always worked because
# its puma had inherited an agent, an undocumented dependency nobody had recorded.
RSpec.describe JobSubmissionService, 'submit-time gStore copy' do
  let(:service) do
    described_class.new(dataset_id: 1, app_name: 'TestApp', parameters: {}, user: 'tester')
  end

  let(:sushi_app) do
    instance_double('SushiApp',
                    scratch_result_dir: '/scratch/run',
                    gstore_project_dir: '/srv/gstore/projects/p1',
                    gstore_script_dir: '/srv/gstore/projects/p1/run/scripts')
  end

  before do
    service.instance_variable_set(:@sushi_app, sushi_app)
    # The NFS-visibility wait is a separate concern and would sleep for 30s here.
    allow(service).to receive(:wait_for_gstore_file).and_return(true)
    # The test environment's storage config selects rsync; these examples are about the FGCZ
    # g-req forms, so pin the method rather than assert against a local-dev command.
    allow(SushiConfigHelper).to receive(:copy_method).and_return('g-req')
  end

  # Capture the command without running it.
  def command_used
    captured = nil
    allow(service).to receive(:run_bounded_copy) do |cmd|
      captured = cmd
      [instance_double(Process::Status, success?: true, exitstatus: 0), '']
    end
    service.send(:copy_scratch_to_gstore)
    captured
  end

  describe 'which g-req form it uses' do
    it 'uses the QUEUED form by default, so it needs no ssh and no agent' do
      expect(command_used).to eq('g-req -w copy /scratch/run /srv/gstore/projects/p1')
    end

    it 'does not use copynow by default, because that path is trxcopy-only' do
      expect(command_used).not_to include('copynow')
    end

    it 'waits for the transfer, because #submit writes rows after this returns' do
      # `-w` is load-bearing, not decoration: the job_manager daemon polls `jobs` and sbatches
      # the script from gStore, so a row whose script has not landed yet is a row it can fail
      # on. Dropping `-w` would leave the suite green and break ordering only in production.
      expect(command_used).to include('-w copy')
    end

    it 'takes the copynow fast path when the instance really runs as trxcopy' do
      allow(SushiConfigHelper).to receive(:submit_copy_now?).and_return(true)
      expect(command_used).to eq('g-req copynow /scratch/run /srv/gstore/projects/p1')
    end
  end

  describe 'when the copy cannot finish' do
    it 'is bounded, so a stalled transfer daemon cannot hold the thread forever' do
      # gtools' own wait() is `while True`. Prove the bound with a real command that would
      # otherwise outlive the example.
      allow(SushiConfigHelper).to receive(:gstore_copy_timeout).and_return(1)
      allow(SushiConfigHelper).to receive(:copy_command).and_return('sleep 30')

      started = Time.now
      expect(service.send(:copy_scratch_to_gstore)).to be false
      expect(Time.now - started).to be < 20
      expect(service.errors.join).to include('timed out after 1s')
    end

    it 'reports the failing command and its output instead of discarding them' do
      allow(SushiConfigHelper).to receive(:copy_command).and_return('sh -c "echo denied >&2; exit 3"')
      allow(Rails.logger).to receive(:error)

      expect(service.send(:copy_scratch_to_gstore)).to be false
      expect(service.errors.join).to include('exit 3')
      expect(Rails.logger).to have_received(:error).with(/denied/)
    end

    it 'still succeeds — and says so — when the copy works' do
      allow(SushiConfigHelper).to receive(:copy_command).and_return('true')
      expect(service.send(:copy_scratch_to_gstore)).to be true
      expect(service.errors).to be_empty
    end
  end

end

RSpec.describe SushiConfigHelper, '.submit_copy_now?' do
  after { ENV.delete('SUSHI_SUBMIT_COPY_NOW') }

  it 'is OFF unless explicitly asked for, so an agentless node works' do
    expect(described_class.submit_copy_now?).to be false
  end

  it 'accepts the documented truthy spellings' do
    %w[1 true TRUE yes].each do |value|
      ENV['SUSHI_SUBMIT_COPY_NOW'] = value
      expect(described_class.submit_copy_now?).to be(true), "expected #{value.inspect} to enable it"
    end
  end

  it 'ignores anything else, so a typo cannot silently pick the trxcopy-only path' do
    ['0', 'false', 'no', 'copynow', ''].each do |value|
      ENV['SUSHI_SUBMIT_COPY_NOW'] = value
      expect(described_class.submit_copy_now?).to be(false), "expected #{value.inspect} to be ignored"
    end
  end

  it 'bounds the copy by default rather than trusting gtools to give up' do
    expect(described_class.gstore_copy_timeout).to eq(900)
  end
end
