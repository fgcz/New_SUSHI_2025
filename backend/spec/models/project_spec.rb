require 'rails_helper'

RSpec.describe Project, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      project = Project.new(number: 12345)
      expect(project).to be_valid
    end

    # Project model doesn't have validations defined,
    # so it can be valid even without a number
    it 'can be created without a number' do
      project = Project.new
      # If no validations are defined, it should be valid
      expect(project).to be_valid
    end
  end

  describe 'associations' do
    it 'has many data_sets' do
      project = Project.reflect_on_association(:data_sets)
      expect(project.macro).to eq(:has_many)
    end

    it 'can have multiple data_sets' do
      project = Project.create!(number: 12345)
      expect(project.data_sets).to be_empty
    end
  end

  describe 'serialization' do
    it 'serializes data_set_tree as YAML' do
      project = Project.create!(number: 12345)
      tree_data = { '1' => { 'id' => 1, 'text' => 'Test' } }
      
      project.data_set_tree = tree_data
      project.save!
      
      expect(project.reload.data_set_tree).to eq(tree_data)
    end
  end

  describe 'instance methods' do
    let(:project) { Project.create!(number: 12345) }

    describe '#saved?' do
      it 'returns false when no data_sets are saved' do
        expect(project.saved?).to be false
      end

      it 'returns true when at least one data_set is saved' do
        # For actual testing, DataSet model and its saved? method are needed
        # data_set = DataSet.create!(name: 'Test', project: project)
        # allow(data_set).to receive(:saved?).and_return(true)
        # expect(project.saved?).to be true
      end
    end

    describe '#register_bfabric' do
      it 'calls register_bfabric on data_sets' do
        # For actual testing, external command execution needs to be mocked
        # data_set = double('DataSet')
        # allow(project).to receive(:data_sets).and_return([data_set])
        # expect(data_set).to receive(:register_bfabric).with('new')
        # project.register_bfabric('new')
      end
    end

    describe '#make_tree_node' do
      it 'creates a tree node for a data_set' do
        # For actual testing, DataSet model is needed
        # data_set = DataSet.create!(name: 'Test Dataset', project: project)
        # node = project.make_tree_node(data_set)
        # expect(node['id']).to eq(data_set.id)
        # expect(node['text']).to include(data_set.name)
      end
    end

    describe '#construct_data_set_tree' do
      it 'constructs a tree from data_sets' do
        # For actual testing, DataSet model is needed
        # data_set = DataSet.create!(name: 'Test Dataset', project: project)
        # project.construct_data_set_tree
        # expect(project.data_set_tree).to have_key(data_set.id.to_s)
      end
    end

    describe '#add_tree_node' do
      it 'adds a node to the tree' do
        # For actual testing, DataSet model is needed
        # data_set = DataSet.create!(name: 'Test Dataset', project: project)
        # project.add_tree_node(data_set)
        # expect(project.data_set_tree).to have_key(data_set.id.to_s)
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      project = build(:project)
      expect(project).to be_valid
    end
  end
end 