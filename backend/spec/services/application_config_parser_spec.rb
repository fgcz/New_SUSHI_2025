require 'rails_helper'

RSpec.describe ApplicationConfigParser do
  describe '.parse' do
    context 'with Fastqc application' do
      subject(:config) { described_class.parse('Fastqc') }

      it 'returns a configuration hash' do
        expect(config).to be_a(Hash)
      end

      it 'extracts basic metadata' do
        expect(config[:name]).to eq('Fastqc')
        expect(config[:class_name]).to eq('FastqcApp')
        expect(config[:analysis_category]).to eq('QC')
        expect(config[:description]).to be_a(String)
        expect(config[:description]).not_to be_empty
      end

      it 'extracts required columns' do
        expect(config[:required_columns]).to include('Name', 'Read1')
      end

      it 'extracts required params' do
        expect(config[:required_params]).to include('paired', 'showNativeReports')
      end

      it 'extracts form fields' do
        expect(config[:form_fields]).to be_an(Array)
        expect(config[:form_fields].size).to be > 0
      end

      it 'extracts modules' do
        expect(config[:modules]).to be_an(Array)
        expect(config[:modules]).to include('QC/FastQC')
      end

      it 'extracts inherit columns' do
        expect(config[:inherit_columns]).to include('Order Id')
      end
    end

    context 'with non-existent application' do
      it 'returns nil' do
        expect(described_class.parse('NonExistentApp')).to be_nil
      end
    end

    context 'with invalid app names' do
      it 'sanitizes directory traversal attempts' do
        expect(described_class.parse('../../../etc/passwd')).to be_nil
      end

      it 'sanitizes special characters' do
        expect(described_class.parse('Fastqc;rm -rf /')).to be_nil
      end
    end
  end

  describe '.list_apps' do
    it 'returns an array of app names' do
      apps = described_class.list_apps
      expect(apps).to be_an(Array)
      expect(apps).to include('Fastqc')
    end

    it 'returns sorted app names' do
      apps = described_class.list_apps
      expect(apps).to eq(apps.sort)
    end
  end

  describe 'field type inference' do
    subject(:config) { described_class.parse('Fastqc') }

    it 'infers select type for array values' do
      cores_field = config[:form_fields].find { |f| f[:name] == 'cores' }
      expect(cores_field[:type]).to eq('select')
      expect(cores_field[:options]).to be_an(Array)
    end

    it 'infers boolean type for boolean values' do
      paired_field = config[:form_fields].find { |f| f[:name] == 'paired' }
      expect(paired_field[:type]).to eq('boolean')
      expect([true, false]).to include(paired_field[:default_value])
    end

    it 'infers text type for string values' do
      special_options_field = config[:form_fields].find { |f| f[:name] == 'specialOptions' }
      expect(special_options_field[:type]).to eq('text')
    end
  end

  describe 'default value extraction' do
    subject(:config) { described_class.parse('Fastqc') }

    it 'extracts first element as default for arrays' do
      cores_field = config[:form_fields].find { |f| f[:name] == 'cores' }
      expect(cores_field[:default_value]).to eq(8)
    end

    it 'uses the value itself for non-arrays' do
      paired_field = config[:form_fields].find { |f| f[:name] == 'paired' }
      expect(paired_field[:default_value]).to eq(false)
    end
  end

  describe 'field descriptions' do
    subject(:config) { described_class.parse('Fastqc') }

    it 'extracts field descriptions when present' do
      ram_field = config[:form_fields].find { |f| f[:name] == 'ram' }
      expect(ram_field[:description]).to eq('GB')
    end

    it 'handles fields without descriptions' do
      paired_field = config[:form_fields].find { |f| f[:name] == 'paired' }
      expect(paired_field[:description]).to be_nil
    end
  end
end

