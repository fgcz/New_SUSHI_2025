require 'rails_helper'

# The gStore browser points at a filesystem shared by every project, so the two
# containment rules ARE the feature: stay under gStore, and only inside project
# directories the caller is authorized for.
RSpec.describe 'Api::V1::Files', type: :request do
  let(:gstore) { Dir.mktmpdir('sushi-files-spec') }

  before do
    allow(SushiConfigHelper).to receive(:gstore_dir).and_return(gstore)
    FileUtils.mkdir_p(File.join(gstore, 'p1001', 'Fastqc_run'))
    FileUtils.mkdir_p(File.join(gstore, 'p2220'))
    File.write(File.join(gstore, 'p1001', 'README.txt'), 'hello')
    File.write(File.join(gstore, 'p1001', 'Fastqc_run', 'S1.html'), '<html>')
  end

  after { FileUtils.remove_entry(gstore) if File.directory?(gstore) }

  context 'when every project is authorized (anonymous mode)' do
    before do
      mock_authentication_skipped(true)
      create(:project, number: 1001)
      create(:project, number: 2220)
    end

    it 'lists the caller s project directories at the root' do
      get '/api/v1/files'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['currentPath']).to eq('/')
      expect(body['parentPath']).to be_nil
      expect(body['items'].map { |i| i['name'] }).to eq(%w[p1001 p2220])
      expect(body['items'].map { |i| i['type'] }.uniq).to eq(['folder'])
    end

    it 'lists a directory with folders before files' do
      get '/api/v1/files', params: { path: 'p1001' }

      body = JSON.parse(response.body)
      expect(body['currentPath']).to eq('p1001')
      expect(body['parentPath']).to be_nil
      expect(body['totalItems']).to eq(2)
      expect(body['items'].map { |i| i['name'] }).to eq(%w[Fastqc_run README.txt])
      expect(body['items'].first['size']).to be_nil
      expect(body['items'].last['size']).to eq(5)
    end

    it 'reports the parent of a nested directory' do
      get '/api/v1/files', params: { path: 'p1001/Fastqc_run' }

      expect(JSON.parse(response.body)['parentPath']).to eq('p1001')
    end

    it 'is 404 for a directory that does not exist' do
      get '/api/v1/files', params: { path: 'p1001/nope' }

      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a path whose first segment is not a project directory' do
      FileUtils.mkdir_p(File.join(gstore, 'etc'))

      get '/api/v1/files', params: { path: 'etc' }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a traversal that climbs out of gStore' do
      get '/api/v1/files', params: { path: 'p1001/../../..' }

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(response.body).not_to include('usr')
    end

    it 'refuses a symlink that points out of gStore' do
      FileUtils.ln_s('/etc', File.join(gstore, 'p1001', 'escape'))

      get '/api/v1/files', params: { path: 'p1001/escape' }

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the caller is scoped to one project' do
    before do
      mock_authentication_skipped(false)
      create(:project, number: 1001)
      create(:project, number: 2220)
      allow_any_instance_of(Api::V1::FilesController)
        .to receive(:authorized_project_numbers).and_return([1001])
      allow_any_instance_of(Api::V1::FilesController)
        .to receive(:skip_jwt_authentication?).and_return(true)
    end

    it 'shows only that project at the root' do
      get '/api/v1/files'

      expect(JSON.parse(response.body)['items'].map { |i| i['name'] }).to eq(['p1001'])
    end

    it 'refuses another project that exists on disk' do
      get '/api/v1/files', params: { path: 'p2220' }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
