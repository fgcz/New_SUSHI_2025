require 'rails_helper'

# SUSHI_ENV_TOKEN_SCOPE=all: the READ credential may read every project in this
# node's database. Added for OMAKASE phase 0, which reads the production node for
# orders whose project is usually new — a numeric list frozen at boot would miss
# exactly those. Every example pins one half of the bargain: wider READ scope, and
# no path by which that scope can ever travel with write authority.
RSpec.describe 'EnvApiToken SCOPE=all' do
  let(:read_raw)  { 'fixture-raw-read-bearer-not-a-real-token' }
  let(:write_raw) { 'fixture-raw-write-bearer-not-a-real-token' }

  def configure_read(scope)
    ENV[EnvApiToken::DIGEST_VAR] = Digest::SHA256.hexdigest(read_raw)
    ENV[EnvApiToken::SCOPE_VAR]  = scope
    ENV[EnvApiToken::NAME_VAR]   = 'omakase-082'
    EnvApiToken.reload!
  end

  def configure_write(scope)
    ENV[EnvApiToken::WRITE_DIGEST_VAR] = Digest::SHA256.hexdigest(write_raw)
    ENV[EnvApiToken::WRITE_SCOPE_VAR]  = scope
    ENV[EnvApiToken::WRITE_NAME_VAR]   = 'cutover-082'
    EnvApiToken.reload!
  end

  around do |example|
    saved = EnvApiToken::VARS.to_h { |v| [v, ENV[v]] }
    EnvApiToken::VARS.each { |v| ENV.delete(v) }
    EnvApiToken.reload!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      EnvApiToken.reload!
    end
  end

  describe 'parsing' do
    it 'accepts `all` for the read credential, with an empty frozen scope' do
      configure_read('all')
      config = EnvApiToken.config
      expect(config.all_projects).to be(true)
      expect(config.scope).to eq([]).and be_frozen
      expect(config.scope_description).to start_with('all (')
      expect(EnvApiToken.errors).to eq([])
    end

    it 'leaves a numeric scope exactly as before' do
      configure_read('35611')
      expect(EnvApiToken.config.all_projects).to be(false)
      expect(EnvApiToken.config.scope_description).to eq('[35611]')
    end

    # Exact match only: anything that merely resembles the keyword is malformed,
    # so a typo can never widen the scope.
    it 'refuses near-misses of the keyword' do
      ['ALL', 'All', '*', 'all,35611', '35611,all', 'allprojects'].each do |bad|
        configure_read(bad)
        expect(EnvApiToken.config).to be_nil, "expected #{bad.inspect} to be refused"
        expect(EnvApiToken.errors.join).to include(EnvApiToken::SCOPE_VAR)
      end
    end

    it 'refuses `all` for the WRITE credential, and says why' do
      configure_read('35611')
      configure_write('all')
      expect(EnvApiToken.write_config).to be_nil
      expect(EnvApiToken.write_enabled?).to be(false)
      expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_SCOPE_VAR)
      expect(EnvApiToken.errors.join).to include('must name its projects')
      # The read credential is unaffected by the write credential's refusal.
      expect(EnvApiToken.config.scope).to eq([35611])
    end
  end

  describe 'the materialized token' do
    let!(:p1001) { create(:project, number: 1001) }
    let!(:p2002) { create(:project, number: 2002) }

    before { configure_read('all') }

    it 'is static, unsaved and read-only' do
      token = EnvApiToken.token_for(read_raw)
      expect(token).to be_static
      expect(token).not_to be_persisted
      expect(token.env_all_projects?).to be(true)
      expect(token.can_write?).to be(false)
    end

    it 'allows every project in the database' do
      expect(EnvApiToken.token_for(read_raw).allowed_projects).to contain_exactly(1001, 2002)
    end

    # The reason `all` is resolved per call instead of being expanded at boot.
    it 'includes a project created after the credential was parsed, without a reload' do
      token = EnvApiToken.token_for(read_raw)
      create(:project, number: 3003)
      expect(token.allowed_projects).to include(3003)
      expect(token.in_scope?(3003)).to be(true)
    end

    it 'answers in_scope? from the database, refusing unknown and non-positive numbers' do
      token = EnvApiToken.token_for(read_raw)
      expect(token.in_scope?(1001)).to be(true)
      expect(token.in_scope?('2002')).to be(true)
      expect(token.in_scope?(9999)).to be(false)
      expect(token.in_scope?(0)).to be(false)
      expect(token.in_scope?(nil)).to be(false)
    end

    it 'writes nothing to api_tokens' do
      expect { EnvApiToken.token_for(read_raw).allowed_projects }.not_to change(ApiToken, :count)
    end
  end

  # Structural, not a convention: the two non-database grants exclude each other in
  # both orders, and neither reaches a persisted row.
  describe 'ApiToken grants' do
    it 'refuses write on an all-projects token' do
      token = ApiToken.new(name: 'x', principal: 'static', scope: [])
      token.grant_env_all_projects!
      expect { token.grant_env_write! }.to raise_error(ArgumentError, /read-only/)
      expect(token.can_write?).to be(false)
    end

    it 'refuses all-projects on a write token' do
      token = ApiToken.new(name: 'x', principal: 'static', scope: [1])
      token.grant_env_write!
      expect { token.grant_env_all_projects! }.to raise_error(ArgumentError, /name its projects/)
      expect(token.env_all_projects?).to be(false)
    end

    it 'refuses all-projects on a persisted row' do
      _raw, row = ApiToken.issue(name: 'reg', scope: [1001])
      expect { row.grant_env_all_projects! }.to raise_error(ArgumentError, /never saved/)
      expect(row.env_all_projects?).to be(false)
    end

    it 'is not assignable through an attributes hash' do
      expect { ApiToken.new(env_all_projects: true) }
        .to raise_error(ActiveModel::UnknownAttributeError)
    end
  end
end
