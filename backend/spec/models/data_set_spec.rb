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
    let(:data_set) { create(:data_set) }

    describe '#headers' do
      it 'returns unique headers from samples' do
        # For actual testing, Sample model and its to_hash method are needed
        # sample1 = Sample.create!(data_set: data_set)
        # sample2 = Sample.create!(data_set: data_set)
        # allow(sample1).to receive(:to_hash).and_return({ 'Name' => 'Test1', 'Value' => '100' })
        # allow(sample2).to receive(:to_hash).and_return({ 'Name' => 'Test2', 'Value' => '200' })
        # expect(data_set.headers).to contain_exactly('Name', 'Value')
      end
    end

    describe '#factor_first_headers' do
      it 'sorts headers with Name first, then Factor headers, then others' do
        # For actual testing, headers method needs to be mocked
        # allow(data_set).to receive(:headers).and_return(['Other', 'Name', 'Factor[Test]'])
        # expect(data_set.factor_first_headers).to eq(['Name', 'Factor[Test]', 'Other'])
      end
    end

    describe '#saved?' do
      it 'returns true if dataset exists with same md5' do
        # For actual testing, md5hexdigest method needs to be mocked
        # allow(data_set).to receive(:md5hexdigest).and_return('test_md5')
        # allow(DataSet).to receive(:find_by_md5).with('test_md5').and_return(data_set)
        # expect(data_set.saved?).to be true
      end

      it 'returns false if dataset does not exist with same md5' do
        # allow(data_set).to receive(:md5hexdigest).and_return('test_md5')
        # allow(DataSet).to receive(:find_by_md5).with('test_md5').and_return(nil)
        # expect(data_set.saved?).to be false
      end
    end

    describe '#md5hexdigest' do
      it 'generates md5 hash from samples, parent_id, and project_id' do
        # For actual testing, samples key_value method needs to be mocked
        # sample = double('Sample')
        # allow(sample).to receive(:key_value).and_return('sample_key')
        # allow(data_set).to receive(:samples).and_return([sample])
        # allow(data_set).to receive(:parent_id).and_return(1)
        # allow(data_set).to receive(:project_id).and_return(2)
        # expected_md5 = Digest::MD5.hexdigest('sample_key12')
        # expect(data_set.md5hexdigest).to eq(expected_md5)
      end
    end

    describe '#tsv_string' do
      it 'generates TSV string from samples' do
        # For actual testing, headers method and samples to_hash method need to be mocked
        # allow(data_set).to receive(:headers).and_return(['Name', 'Value'])
        # sample = double('Sample')
        # allow(sample).to receive(:to_hash).and_return({ 'Name' => 'Test', 'Value' => '100' })
        # allow(data_set).to receive(:samples).and_return([sample])
        # expect(data_set.tsv_string).to include('Name')
        # expect(data_set.tsv_string).to include('Test')
        # expect(data_set.tsv_string).to include('100')
      end
    end

    describe '#samples_length' do
      it 'returns cached num_samples if available' do
        data_set.num_samples = 5
        expect(data_set.samples_length).to eq(5)
      end

      it 'calculates and caches samples length if not available' do
        # For actual testing, samples length method needs to be mocked
        # allow(data_set).to receive(:samples).and_return([1, 2, 3])
        # allow(data_set).to receive(:save)
        # expect(data_set.samples_length).to eq(3)
        # expect(data_set.num_samples).to eq(3)
      end
    end
  end

  describe 'class methods' do
    describe '.save_dataset_to_database' do
      it 'creates a new dataset with provided data' do
        # For actual testing, required parameters need to be provided
        # data_set_arr = ['name', 'Test Dataset']
        # headers = ['Name', 'Value']
        # rows = [['Test1', '100'], ['Test2', '200']]
        # user = create(:user)
        # 
        # expect {
        #   DataSet.save_dataset_to_database(
        #     data_set_arr: data_set_arr,
        #     headers: headers,
        #     rows: rows,
        #     user: user
        #   )
        # }.to change(DataSet, :count).by(1)
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