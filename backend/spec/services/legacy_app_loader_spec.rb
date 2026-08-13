require 'rails_helper'

RSpec.describe LegacyAppLoader do
  let(:fixture_dir) { Rails.root.join('spec', 'fixtures', 'legacy_apps').to_s }

  # Point the loader at the fixture legacy dir with FooBar allow-listed, restore after.
  around do |example|
    cfg = Rails.application.config
    old_dir = cfg.legacy_apps_dir
    old_list = cfg.legacy_apps_allowlist
    cfg.legacy_apps_dir = fixture_dir
    cfg.legacy_apps_allowlist = ['FooBar']
    example.run
  ensure
    cfg.legacy_apps_dir = old_dir
    cfg.legacy_apps_allowlist = old_list
  end

  describe '.normalize' do
    it 'adds the App suffix and strips unsafe characters' do
      expect(described_class.normalize('FooBar')).to eq('FooBarApp')
      expect(described_class.normalize('FooBarApp')).to eq('FooBarApp')
      expect(described_class.normalize('../../etc/passwd')).to eq('etcpasswdApp')
    end
  end

  describe '.list_apps' do
    it 'includes native apps and allow-listed legacy apps, sorted & deduped' do
      apps = described_class.list_apps
      expect(apps).to include('Fastqc') # native
      expect(apps).to include('FooBar') # allow-listed legacy
      expect(apps).to eq(apps.sort.uniq)
    end
  end

  describe '.available?' do
    it 'is true for native and allow-listed legacy apps' do
      expect(described_class.available?('Fastqc')).to be(true)
      expect(described_class.available?('FooBar')).to be(true)
    end

    it 'is false for a legacy app file that is not allow-listed' do
      # NotListedApp.rb does not exist and is not allow-listed
      expect(described_class.available?('NotListed')).to be(false)
    end
  end

  # The legacy dir holds families of same-prefix apps: CellRangerApp.rb sits next to
  # CellRangerARCApp.rb, CellRangerATACApp.rb and CellRangerAggrApp.rb. Allow-listing
  # 'CellRanger' must expose exactly one of them. FooBarApp / FooBarExtraApp reproduce
  # that shape, so a regression to prefix/substring matching fails here instead of
  # silently exposing unverified apps through the API.
  describe 'allow-list matching is exact, not by prefix' do
    it 'does not expose a longer app name that starts with an allow-listed entry' do
      # allow-list is ['FooBar']; FooBarExtraApp.rb exists in the same fixture dir.
      expect(File.exist?(File.join(fixture_dir, 'FooBarExtraApp.rb'))).to be(true)
      expect(described_class.available?('FooBarExtra')).to be(false)
      expect(described_class.load('FooBarExtra')).to be_nil
      expect(described_class.list_apps).not_to include('FooBarExtra')
    end

    it 'does not expose a shorter app name that an allow-listed entry starts with' do
      Rails.application.config.legacy_apps_allowlist = ['FooBarExtra']
      expect(described_class.available?('FooBarExtra')).to be(true)
      expect(described_class.available?('FooBar')).to be(false)
      expect(described_class.load('FooBar')).to be_nil
      expect(described_class.list_apps).not_to include('FooBar')
    end
  end

  describe '.load' do
    it 'loads an allow-listed legacy app onto the backend shim' do
      klass = described_class.load('FooBar')
      expect(klass).to eq(FooBarApp)
      expect(klass.ancestors).to include(SushiFabric::SushiApp)
      inst = klass.new
      expect(inst.name).to eq('FooBar')
    end

    it 'loads native apps and they win over legacy of the same name' do
      klass = described_class.load('Fastqc')
      expect(klass.name).to eq('FastqcApp')
    end

    it 'returns nil for an unknown app' do
      expect(described_class.load('DefinitelyNotAnApp')).to be_nil
    end
  end
end
