require 'rails_helper'

# The job script and its two logs are the only job artefacts the UI shows.
# They are read straight off disk from paths stored in the jobs row, so the
# guard against reading anything outside gStore/scratch is part of the contract.
RSpec.describe 'Api::V1::Jobs script and logs', type: :request do
  before { mock_authentication_skipped(true) }

  let(:gstore) { Dir.mktmpdir('sushi-job-files-spec') }
  let(:scripts_dir) { File.join(gstore, 'p1001', 'Fastqc_2026', 'scripts') }
  let(:script_path) { File.join(scripts_dir, 'Fastqc_9.sh') }
  let(:stdout_path) { "#{script_path}_o.log" }
  let(:stderr_path) { "#{script_path}_e.log" }

  before do
    allow(SushiConfigHelper).to receive(:gstore_dir).and_return(gstore)
    FileUtils.mkdir_p(scripts_dir)
  end

  after { FileUtils.remove_entry(gstore) if File.directory?(gstore) }

  let(:project) { create(:project, number: 1001) }
  let(:dataset) { create(:data_set, project: project) }
  let(:job) { create(:job, data_set: dataset, script_path: script_path) }

  describe 'GET /api/v1/jobs/:id/script' do
    it 'returns the script with its absolute path recorded as line 2' do
      File.write(script_path, "#!/bin/bash\nmodule add QC/FastQC\necho done\n")

      get "/api/v1/jobs/#{job.id}/script"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['path']).to eq(script_path)
      expect(body['script'].lines[0]).to eq("#!/bin/bash\n")
      expect(body['script'].lines[1]).to eq("##{script_path}\n")
      expect(body['script'].lines[2]).to eq("module add QC/FastQC\n")
    end

    it 'leaves a one-line script alone' do
      File.write(script_path, '#!/bin/bash')

      get "/api/v1/jobs/#{job.id}/script"

      expect(JSON.parse(response.body)['script']).to eq('#!/bin/bash')
    end

    it 'is 404 when the file is gone' do
      get "/api/v1/jobs/#{job.id}/script"

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('Script not found')
    end

    it 'is 404 when the row carries no script path' do
      pathless = create(:job, data_set: dataset, script_path: nil)

      get "/api/v1/jobs/#{pathless.id}/script"

      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a path outside gStore even though the row names it' do
      outside = Tempfile.new('outside-gstore')
      outside.write("#!/bin/bash\nwhoami\n")
      outside.flush
      escaped = create(:job, data_set: dataset, script_path: outside.path)

      get "/api/v1/jobs/#{escaped.id}/script"

      expect(response).to have_http_status(:not_found)
    ensure
      outside&.close!
    end

    it 'refuses a traversal that climbs back out of gStore' do
      secret = Tempfile.new('outside-traversal')
      secret.write('secret')
      secret.flush
      traversal = create(:job, data_set: dataset,
                               script_path: File.join(scripts_dir, '..', '..', '..', '..', secret.path))

      get "/api/v1/jobs/#{traversal.id}/script"

      expect(response).to have_http_status(:not_found)
    ensure
      secret&.close!
    end

    it 'is 404 for an unknown job' do
      get '/api/v1/jobs/999999/script'

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('Job not found')
    end
  end

  describe 'GET /api/v1/jobs/:id/logs' do
    let(:job) do
      create(:job, data_set: dataset, script_path: script_path,
                   stdout_path: stdout_path, stderr_path: stderr_path)
    end

    it 'concatenates stdout and stderr with legacy markers' do
      File.write(stdout_path, "Starting\nDone\n")
      File.write(stderr_path, "warning: none\n")

      get "/api/v1/jobs/#{job.id}/logs"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['stdout_path']).to eq(stdout_path)
      expect(body['stderr_path']).to eq(stderr_path)
      expect(body['logs']).to include('Starting', 'warning: none')
      expect(body['logs']).to include('___STDOUT_END___', '___STDERR_END___')
      expect(body['logs'].index('___STDOUT_END___')).to be < body['logs'].index('___STDERR_END___')
    end

    it 'is 404 when only one of the two exists, as legacy requires both' do
      File.write(stdout_path, "Starting\n")

      get "/api/v1/jobs/#{job.id}/logs"

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('Logs not found')
    end

    # This is where a job's logs live for its whole run; only when it completes
    # do they move into the gStore result dir. Confining reads to gStore alone
    # made every RUNNING job report "Logs not found".
    it 'serves logs from the daemon staging directory of a running job' do
      staging = Dir.mktmpdir('sushi-job-logs-spec')
      allow(SushiConfigHelper).to receive(:job_log_dirs).and_return([staging])
      running_out = File.join(staging, 'Fastqc_9.sh_sushiID789_o.log')
      running_err = File.join(staging, 'Fastqc_9.sh_sushiID789_e.log')
      File.write(running_out, "Started\n")
      File.write(running_err, '')
      running = create(:job, data_set: dataset, status: 'RUNNING',
                             stdout_path: running_out, stderr_path: running_err)

      get "/api/v1/jobs/#{running.id}/logs"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['logs']).to include('Started')
    ensure
      FileUtils.remove_entry(staging) if staging && File.directory?(staging)
    end

    # The staging directory MOVED, and one configured path is what made a real
    # RUNNING job on 082 answer "Logs not found" while its file sat there
    # world-readable. Both locations must be served, and neither may shadow the
    # other.
    it 'serves logs from EITHER configured staging directory' do
      old_dir = Dir.mktmpdir('sushi-job-logs-old')
      new_dir = Dir.mktmpdir('sushi-job-logs-new')
      allow(SushiConfigHelper).to receive(:job_log_dirs).and_return([new_dir, old_dir])

      [[old_dir, 'from-the-old-location'], [new_dir, 'from-the-new-location']].each do |dir, marker|
        out = File.join(dir, "#{marker}_o.log")
        err = File.join(dir, "#{marker}_e.log")
        File.write(out, "#{marker}\n")
        File.write(err, '')
        job = create(:job, data_set: dataset, status: 'RUNNING',
                           stdout_path: out, stderr_path: err)

        get "/api/v1/jobs/#{job.id}/logs"

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['logs']).to include(marker)
      end
    ensure
      [old_dir, new_dir].compact.each { |d| FileUtils.remove_entry(d) if File.directory?(d) }
    end

    # Widening the allow-list must not have removed it.
    it 'still refuses a log path outside every configured directory' do
      elsewhere = Dir.mktmpdir('sushi-job-logs-elsewhere')
      allow(SushiConfigHelper).to receive(:job_log_dirs).and_return([Dir.mktmpdir('sushi-allowed')])
      out = File.join(elsewhere, 'sneaky_o.log')
      err = File.join(elsewhere, 'sneaky_e.log')
      File.write(out, "secret\n")
      File.write(err, '')
      job = create(:job, data_set: dataset, status: 'RUNNING',
                         stdout_path: out, stderr_path: err)

      get "/api/v1/jobs/#{job.id}/logs"

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('Logs not found')
    ensure
      FileUtils.remove_entry(elsewhere) if elsewhere && File.directory?(elsewhere)
    end

    it 'is 404 when the row carries no log paths' do
      pathless = create(:job, data_set: dataset, stdout_path: nil, stderr_path: nil)

      get "/api/v1/jobs/#{pathless.id}/logs"

      expect(response).to have_http_status(:not_found)
    end
  end
end
