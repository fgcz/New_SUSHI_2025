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

  describe 'param_groups' do
    # The frontend's run-application page steps through param_groups; when it is
    # empty the block holding the submit button is not rendered at all.
    def parse_fixture(app_name)
      cfg = Rails.application.config
      old_dir = cfg.legacy_apps_dir
      old_list = cfg.legacy_apps_allowlist
      cfg.legacy_apps_dir = Rails.root.join('spec', 'fixtures', 'legacy_apps').to_s
      cfg.legacy_apps_allowlist = [app_name]
      described_class.parse(app_name)
    ensure
      cfg.legacy_apps_dir = old_dir
      cfg.legacy_apps_allowlist = old_list
    end

    context 'an app with no section headers' do
      subject(:config) { described_class.parse('Fastqc') }

      it 'returns exactly one group holding every field' do
        expect(config[:param_groups].size).to eq(1)
        expect(config[:param_groups].first[:fields]).to eq(config[:form_fields])
      end

      it 'titles it with the default, since legacy leaves the first section unnamed' do
        expect(config[:param_groups].first[:title]).to eq('Parameters')
        expect(config[:param_groups].first[:id]).to eq('parameters')
      end
    end

    context 'an app with section headers' do
      subject(:config) { parse_fixture('FooBarSections') }

      it 'opens a new group at every header and keeps the leading one' do
        expect(config[:param_groups].map { |g| g[:title] })
          .to eq(['Parameters', 'AI summaries', 'Notification'])
      end

      it 'derives the id from the title' do
        expect(config[:param_groups].map { |g| g[:id] })
          .to eq(%w[parameters ai_summaries notification])
      end

      it 'puts the header-carrying field inside the section it opens' do
        ai_group = config[:param_groups].find { |g| g[:title] == 'AI summaries' }
        expect(ai_group[:fields].map { |f| f[:name] }).to eq(%w[generate_ai_summary ai_model])
      end

      it 'loses no field: the groups partition form_fields in order' do
        expect(config[:param_groups].flat_map { |g| g[:fields] }).to eq(config[:form_fields])
      end

      it 'keeps the header-carrying field editable instead of typing it as a section' do
        field = config[:form_fields].find { |f| f[:name] == 'generate_ai_summary' }
        expect(field[:type]).to eq('boolean')
        expect(field[:section_header]).to eq('AI summaries')
      end
    end

    context 'a Hash-valued parameter such as refBuild' do
      subject(:config) { parse_fixture('FooBarSections') }

      let(:field) { config[:form_fields].find { |f| f[:name] == 'refBuild' } }

      it 'becomes a selector over the submittable values, not a text box' do
        expect(field[:type]).to eq('select')
        expect(field[:options]).to eq(['', 'Homo_sapiens/GENCODE/GRCh38.p13'])
      end

      it 'defaults to the first entry rather than dumping the whole Hash' do
        expect(field[:default_value]).to eq('')
      end

      it 'carries the labels only when they differ from the values' do
        expect(field[:option_labels]).to eq(['select', 'Homo_sapiens/GENCODE/GRCh38.p13'])
      end
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

