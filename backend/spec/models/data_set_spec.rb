require 'rails_helper'

RSpec.describe DataSet, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      user = create(:user)
      project = create(:project)
      data_set = DataSet.new(
        name: 'Test Dataset',
        user: user,
        project: project
      )
      expect(data_set).to be_valid
    end

    it 'is not valid without a name' do
      user = create(:user)
      project = create(:project)
      data_set = DataSet.new(
        user: user,
        project: project
      )
      expect(data_set).not_to be_valid
      expect(data_set.errors[:name]).to include("can't be blank")
    end

    it 'is not valid without a project' do
      user = create(:user)
      data_set = DataSet.new(
        name: 'Test Dataset',
        user: user
      )
      expect(data_set).not_to be_valid
      expect(data_set.errors[:project]).to include('must exist')
    end

    it 'is not valid without a user' do
      project = create(:project)
      data_set = DataSet.new(
        name: 'Test Dataset',
        project: project
      )
      expect(data_set).not_to be_valid
      expect(data_set.errors[:user]).to include('must exist')
    end
  end

  describe 'associations' do
    it 'has many samples' do
      data_set = DataSet.reflect_on_association(:samples)
      expect(data_set.macro).to eq(:has_many)
    end

    it 'has many jobs' do
      data_set = DataSet.reflect_on_association(:jobs)
      expect(data_set.macro).to eq(:has_many)
    end

    it 'belongs to project' do
      data_set = DataSet.reflect_on_association(:project)
      expect(data_set.macro).to eq(:belongs_to)
    end

    it 'has many data_sets' do
      data_set = DataSet.reflect_on_association(:data_sets)
      expect(data_set.macro).to eq(:has_many)
    end

    it 'belongs to data_set' do
      data_set = DataSet.reflect_on_association(:data_set)
      expect(data_set.macro).to eq(:belongs_to)
    end

    it 'belongs to user' do
      data_set = DataSet.reflect_on_association(:user)
      expect(data_set.macro).to eq(:belongs_to)
    end
  end

  describe 'serialization' do
    it 'serializes runnable_apps as YAML' do
      data_set = create(:data_set)
      apps = ['app1', 'app2']
      
      data_set.runnable_apps = apps
      data_set.save!
      
      expect(data_set.reload.runnable_apps).to eq(apps)
    end

    it 'serializes order_ids as YAML' do
      data_set = create(:data_set)
      order_ids = [123, 456]
      
      data_set.order_ids = order_ids
      data_set.save!
      
      expect(data_set.reload.order_ids).to eq(order_ids)
    end

    it 'serializes job_parameters as YAML' do
      data_set = create(:data_set)
      params = { 'param1' => 'value1', 'param2' => 'value2' }
      
      data_set.job_parameters = params
      data_set.save!
      
      expect(data_set.reload.job_parameters).to eq(params)
    end
  end

  describe 'instance methods' do
    let(:user) { create(:user) }
    let(:project) { create(:project, number: 1001) }
    let(:data_set) { create(:data_set, user: user, project: project) }

    describe '#headers' do
      it 'returns unique headers from samples' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'Test1', 'Value' => '100'}")
        create(:sample, data_set: data_set, key_value: "{'Name' => 'Test2', 'Value' => '200'}")
        
        expect(data_set.headers).to contain_exactly('Name', 'Value')
      end

      it 'returns empty array when no samples' do
        expect(data_set.headers).to eq([])
      end
    end

    describe '#factor_first_headers' do
      it 'sorts headers with Name first, then Factor headers, then others' do
        create(:sample, data_set: data_set, key_value: "{'Other' => 'val', 'Name' => 'Test', 'Condition [Factor]' => 'A'}")
        
        headers = data_set.factor_first_headers
        expect(headers.first).to eq('Name')
        expect(headers.last).to eq('Other')
      end
    end

    describe '#saved?' do
      it 'returns false when no dataset with same md5 exists' do
        expect(data_set.saved?).to be false
      end

      it 'returns true when dataset with same md5 exists' do
        data_set.md5 = data_set.md5hexdigest
        data_set.save!
        expect(data_set.saved?).to be true
      end
    end

    describe '#md5hexdigest' do
      it 'generates md5 hash from samples, parent_id, and project_id' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'Sample1'}")
        
        md5 = data_set.md5hexdigest
        expect(md5).to be_a(String)
        expect(md5.length).to eq(32)
      end

      it 'generates different md5 for different content' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'Sample1'}")
        md5_1 = data_set.md5hexdigest
        
        # Create a different dataset with different samples
        data_set2 = create(:data_set, user: user, project: project)
        create(:sample, data_set: data_set2, key_value: "{'Name' => 'DifferentSample'}")
        md5_2 = data_set2.md5hexdigest
        
        expect(md5_1).not_to eq(md5_2)
      end
    end

    describe '#tsv_string' do
      it 'generates TSV string from samples' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'Test', 'Value' => '100'}")
        
        tsv = data_set.tsv_string
        expect(tsv).to include('Name')
        expect(tsv).to include('Test')
        expect(tsv).to include('100')
      end

      it 'generates TSV with tab separators' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'Test', 'Value' => '100'}")
        
        tsv = data_set.tsv_string
        expect(tsv).to include("\t")
      end

      it 'returns empty or minimal TSV when no samples' do
        tsv = data_set.tsv_string
        # With no samples and no headers, TSV is just a newline or empty
        expect(tsv.strip).to eq("")
      end
    end

    describe '#samples_length' do
      it 'returns cached num_samples if available' do
        data_set.num_samples = 5
        expect(data_set.samples_length).to eq(5)
      end

      it 'calculates and caches samples length if not available' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1'}")
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S2'}")
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S3'}")
        
        data_set.num_samples = nil
        expect(data_set.samples_length).to eq(3)
        expect(data_set.reload.num_samples).to eq(3)
      end
    end

    describe '#paths' do
      it 'extracts unique directory paths from file columns' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1', 'Read1 [File]' => 'p1001/data/file1.fastq'}")
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S2', 'Read1 [File]' => 'p1001/data/file2.fastq'}")
        
        paths = data_set.paths
        expect(paths).to include('p1001/data')
      end
    end

    describe '#sample_paths' do
      it 'extracts unique sample paths from file columns' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1', 'Read1 [File]' => 'p1001/data/file1.fastq'}")
        
        paths = data_set.sample_paths
        expect(paths).to be_an(Array)
      end

      it 'handles samples without file columns gracefully' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1', 'Value' => '100'}")
        
        expect { data_set.sample_paths }.not_to raise_error
      end
    end

    describe '#file_paths' do
      it 'returns all file paths from samples' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1', 'Read1 [File]' => 'p1001/data/file1.fastq'}")
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S2', 'Read1 [File]' => 'p1001/data/file2.fastq'}")
        
        paths = data_set.file_paths
        expect(paths).to include('p1001/data/file1.fastq')
        expect(paths).to include('p1001/data/file2.fastq')
      end

      it 'returns unique file paths' do
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1', 'Read1 [File]' => 'p1001/data/file.fastq'}")
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S2', 'Read1 [File]' => 'p1001/data/file.fastq'}")
        
        paths = data_set.file_paths
        expect(paths.count { |p| p == 'p1001/data/file.fastq' }).to eq(1)
      end
    end

    describe '#check_order_ids' do
      it 'extracts order IDs from samples' do
        data_set.order_ids = []
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1', 'Order Id [B-Fabric]' => '12345'}")
        
        data_set.check_order_ids
        expect(data_set.order_ids).to include('12345')
      end

      it 'sets order_id when only one unique order ID' do
        data_set.order_ids = []
        create(:sample, data_set: data_set, key_value: "{'Name' => 'S1', 'Order Id [B-Fabric]' => '12345'}")
        
        data_set.check_order_ids
        expect(data_set.order_id).to eq(12345)
      end
    end
  end

  describe 'class methods' do
    describe '.save_dataset_to_database' do
      let(:user) { create(:user) }

      it 'creates a new dataset with provided data' do
        data_set_arr = ['DataSetName', 'Test Dataset', 'ProjectNumber', '1001']
        headers = ['Name', 'Value']
        rows = [['Test1', '100'], ['Test2', '200']]
        
        expect {
          DataSet.save_dataset_to_database(
            data_set_arr: data_set_arr,
            headers: headers,
            rows: rows,
            user: user
          )
        }.to change(DataSet, :count).by(1)
      end

      it 'creates samples for the dataset' do
        data_set_arr = ['DataSetName', 'Test Dataset', 'ProjectNumber', '1001']
        headers = ['Name', 'Value']
        rows = [['Test1', '100'], ['Test2', '200']]
        
        expect {
          DataSet.save_dataset_to_database(
            data_set_arr: data_set_arr,
            headers: headers,
            rows: rows,
            user: user
          )
        }.to change(Sample, :count).by(2)
      end

      it 'creates project if it does not exist' do
        data_set_arr = ['DataSetName', 'Test Dataset', 'ProjectNumber', '9999']
        headers = ['Name']
        rows = [['Test1']]
        
        expect {
          DataSet.save_dataset_to_database(
            data_set_arr: data_set_arr,
            headers: headers,
            rows: rows,
            user: user
          )
        }.to change(Project, :count).by(1)
      end

      it 'sets parent dataset when ParentID is provided' do
        parent = create(:data_set, user: user)
        data_set_arr = ['DataSetName', 'Child Dataset', 'ProjectNumber', '1001', 'ParentID', parent.id.to_s]
        headers = ['Name']
        rows = [['Test1']]
        
        dataset_id = DataSet.save_dataset_to_database(
          data_set_arr: data_set_arr,
          headers: headers,
          rows: rows,
          user: user
        )
        
        dataset = DataSet.find(dataset_id)
        expect(dataset.parent_id).to eq(parent.id)
      end

      it 'sets comment when provided' do
        data_set_arr = ['DataSetName', 'Test Dataset', 'ProjectNumber', '1001', 'Comment', 'Test comment']
        headers = ['Name']
        rows = [['Test1']]
        
        dataset_id = DataSet.save_dataset_to_database(
          data_set_arr: data_set_arr,
          headers: headers,
          rows: rows,
          user: user
        )
        
        dataset = DataSet.find(dataset_id)
        expect(dataset.comment).to eq('Test comment')
      end

      it 'sets sushi_app_name when provided' do
        data_set_arr = ['DataSetName', 'Test Dataset', 'ProjectNumber', '1001']
        headers = ['Name']
        rows = [['Test1']]
        
        dataset_id = DataSet.save_dataset_to_database(
          data_set_arr: data_set_arr,
          headers: headers,
          rows: rows,
          user: user,
          sushi_app_name: 'FastqcApp'
        )
        
        dataset = DataSet.find(dataset_id)
        expect(dataset.sushi_app_name).to eq('FastqcApp')
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      data_set = build(:data_set)
      expect(data_set).to be_valid
    end
  end
end 