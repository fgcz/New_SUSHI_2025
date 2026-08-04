require 'rails_helper'

# The ENV-provisioned bearer credential: a DB-free token for the production node,
# whose `api_tokens` table belongs to legacy SUSHI and may be neither written nor
# altered. Every example here pins one of the invariants named in
# lib/env_api_token.rb; they are the reason this path is safe to have at all.
RSpec.describe EnvApiToken do
  let(:raw)    { 'fixture-raw-bearer-value-not-a-real-token' }
  let(:sha256) { Digest::SHA256.hexdigest(raw) }

  # ENV is parsed once per process by design, so an example that wants a
  # credential must set the variables and re-parse explicitly.
  def configure(digest: sha256, scope: '35611', name: 'chain-082')
    ENV[described_class::DIGEST_VAR] = digest
    ENV[described_class::SCOPE_VAR]  = scope
    ENV[described_class::NAME_VAR]   = name
    described_class.reload!
  end

  around do |example|
    saved = described_class::VARS.to_h { |v| [v, ENV[v]] }
    described_class::VARS.each { |v| ENV.delete(v) }
    described_class.reload!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      described_class.reload!
    end
  end

  # INV-1
  describe 'when no variables are set (every node but the production one)' do
    it 'has no credential, no errors and authenticates nothing' do
      expect(described_class.config).to be_nil
      expect(described_class.enabled?).to be(false)
      expect(described_class.intended?).to be(false)
      expect(described_class.errors).to eq([])
      expect(described_class.token_for(raw)).to be_nil
    end

    it 'leaves ApiToken.authenticate behaving exactly as before' do
      db_raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])
      expect(ApiToken.authenticate(db_raw)).to eq(db_token)
      expect(ApiToken.authenticate('nope')).to be_nil
    end
  end

  # INV-2 — fail-closed on every partial or malformed configuration.
  describe 'fail-closed validation' do
    it 'rejects a digest that is not 64 lowercase hex characters' do
      [sha256.upcase, sha256[0..62], "#{sha256}f", 'not-a-digest'].each do |bad|
        configure(digest: bad)
        expect(described_class.config).to be_nil
        expect(described_class.errors.join).to include(described_class::DIGEST_VAR)
      end
    end

    it 'rejects an absent, empty or non-numeric scope' do
      ['', ' ', '0', 'p35611', '35611,abc', '-1'].each do |bad|
        configure(scope: bad)
        expect(described_class.config).to be_nil
        expect(described_class.errors.join).to include(described_class::SCOPE_VAR)
      end
    end

    it 'rejects a blank name' do
      configure(name: '  ')
      expect(described_class.config).to be_nil
      expect(described_class.errors.join).to include(described_class::NAME_VAR)
    end

    # The name reaches a log line and the synthetic `apitoken:<name>` login, and
    # the provisioning task prints it inside a shell `export`. A newline would
    # forge a log record; a semicolon or backtick would be shell injection on
    # paste. Restrict the charset instead of escaping in three places.
    it 'rejects a name that could forge a log record or inject into a shell' do
      ["two words", "a;rm -rf /", "back`tick`", "new\nline", 'a$(id)', 'x' * 65].each do |bad|
        configure(name: bad)
        expect(described_class.config).to be_nil
        expect(described_class.errors.join).to include(described_class::NAME_VAR)
      end
    end

    it 'accepts the conventional name shapes' do
      %w[chain-082 chain_082 chain.082 CHAIN082 a].each do |good|
        configure(name: good)
        expect(described_class.config&.name).to eq(good)
      end
    end

    it 'reports intent even when the configuration is invalid, so the misconfiguration is not silent' do
      configure(digest: 'garbage')
      expect(described_class.enabled?).to be(false)
      expect(described_class.intended?).to be(true)
    end

    it 'treats a digest with no scope as a misconfiguration rather than an unscoped credential' do
      ENV[described_class::DIGEST_VAR] = sha256
      described_class.reload!
      expect(described_class.config).to be_nil
    end
  end

  describe 'a valid credential' do
    before { configure }

    it 'parses and freezes name, scope and digest' do
      config = described_class.config
      expect(config.name).to eq('chain-082')
      expect(config.scope).to eq([35611])
      expect(config).to be_frozen
      expect(config.scope).to be_frozen
      expect(described_class.errors).to eq([])
    end

    # ActiveRecord's serialized reader hands out a per-object copy, so the frozen
    # array cannot be pushed all the way through to `token.scope`. What matters is
    # that the SOURCE of authority is immutable: mutating one token's scope must
    # not widen the credential for the next request.
    it 'keeps the source of authority immutable against a mutated token scope' do
      token = described_class.token_for(raw)
      token.scope << 999

      expect(described_class.config.scope).to eq([35611]).and be_frozen
      expect(described_class.token_for(raw).allowed_projects).to eq([35611])
    end

    it 'accepts a multi-project scope' do
      configure(scope: '35611, 1001 ,2002')
      expect(described_class.config.scope).to eq([35611, 1001, 2002])
    end

    # INV-3
    it 'refuses any raw value other than the configured one' do
      expect(described_class.token_for('wrong')).to be_nil
      expect(described_class.token_for('')).to be_nil
      expect(described_class.token_for(nil)).to be_nil
      expect(described_class.token_for(sha256)).to be_nil # the digest is not the token
    end

    # INV-4, INV-5, INV-8
    it 'materializes an unsaved, static, read-only ApiToken' do
      expect { described_class.token_for(raw) }.not_to change(ApiToken, :count)

      token = described_class.token_for(raw)
      expect(token).to be_a(ApiToken)
      expect(token.persisted?).to be(false)
      expect(token.id).to be_nil
      expect(token.principal).to eq('static')
      expect(token.static?).to be(true)
      expect(token.user?).to be(false)
      expect(token.machine?).to be(false)
      expect(token.name).to eq('chain-082')
      expect(token.active?).to be(true)
      expect(token.effective_capabilities).to eq(%w[read])
      expect(token.can_write?).to be(false)
      expect(token.in_scope?(35611)).to be(true)
      expect(token.in_scope?(1001)).to be(false)
      expect(token.allowed_projects).to eq([35611])
    end

    it 'never assigns capabilities, so the credential cannot be promoted to a writer' do
      # Nothing is granted: the serialized Array reads as empty (AR casts the
      # unset attribute), which is what makes effective_capabilities fail closed.
      # Not assigning it is also what keeps this working on the production node,
      # where the column does not exist at all and an assignment would raise
      # ActiveModel::UnknownAttributeError.
      token = described_class.token_for(raw)
      expect(Array(token.capabilities)).to eq([])
      expect(token.effective_capabilities).to eq(%w[read])
      expect(token.can_write?).to be(false)
    end

    # INV-9
    it 'ignores ENV changes made after the credential was parsed' do
      ENV[described_class::DIGEST_VAR] = Digest::SHA256.hexdigest('an-attackers-token')
      ENV[described_class::SCOPE_VAR]  = '1'
      expect(described_class.token_for(raw).allowed_projects).to eq([35611])
      expect(described_class.token_for('an-attackers-token')).to be_nil
    end
  end

  describe '.digest_of' do
    it 'is the plain SHA-256 the rake task and the server agree on' do
      expect(described_class.digest_of(raw)).to eq(sha256)
      # Deliberately NOT the secret_key_base-salted ApiToken.digest: the ENV
      # credential must survive a secret rotation.
      expect(described_class.digest_of(raw)).not_to eq(ApiToken.digest(raw))
    end
  end

  describe '.reload!' do
    it 'refuses to run outside the test environment, so production cannot undo the freeze' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect { described_class.reload! }.to raise_error(/test-only/)
    end
  end

  describe 'integration with ApiToken.authenticate' do
    before { configure }

    it 'authenticates the ENV credential on a DB miss' do
      token = ApiToken.authenticate(raw)
      expect(token).to be_a(ApiToken)
      expect(token.persisted?).to be(false)
      expect(token.name).to eq('chain-082')
    end

    it 'still prefers a live DB row' do
      db_raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])
      expect(ApiToken.authenticate(db_raw)).to eq(db_token)
    end

    # INV-6 — the ENV path must not become a way to revive a withdrawn credential.
    it 'does not rescue a revoked DB row even when the ENV digest matches the same raw value' do
      db_raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])
      db_token.update!(revoked_at: Time.now)
      configure(digest: Digest::SHA256.hexdigest(db_raw))

      expect(ApiToken.authenticate(db_raw)).to be_nil
    end

    it 'does not rescue an expired DB row even when the ENV digest matches the same raw value' do
      db_raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])
      db_token.update!(expires_at: 1.day.ago)
      configure(digest: Digest::SHA256.hexdigest(db_raw))

      expect(ApiToken.authenticate(db_raw)).to be_nil
    end

    # INV-7
    it 'logs a failed attempt without ever revealing the token or its digest' do
      messages = []
      allow(Rails.logger).to receive(:warn) { |m| messages << m.to_s }

      expect(ApiToken.authenticate('some-wrong-token')).to be_nil

      expect(messages).not_to be_empty
      expect(messages.join).not_to include('some-wrong-token')
      expect(messages.join).not_to include(sha256)
      expect(messages.join).not_to include(raw)
    end

    # The revoked/expired branch returns before the ENV lookup (INV-6), so it once
    # returned before the log line too — leaving a client that keeps presenting a
    # withdrawn token completely invisible, which is the opposite of the point.
    it 'logs when a revoked DB row is presented, not only on an unknown token' do
      db_raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])
      db_token.update!(revoked_at: Time.now)

      messages = []
      allow(Rails.logger).to receive(:warn) { |m| messages << m.to_s }

      expect(ApiToken.authenticate(db_raw)).to be_nil
      expect(messages.join).to include('bearer authentication failed')
      expect(messages.join).not_to include(db_raw)
    end

    it 'logs when an expired DB row is presented' do
      db_raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])
      db_token.update!(expires_at: 1.day.ago)

      messages = []
      allow(Rails.logger).to receive(:warn) { |m| messages << m.to_s }

      expect(ApiToken.authenticate(db_raw)).to be_nil
      expect(messages.join).to include('bearer authentication failed')
    end

    it 'stays silent about failures on a node that never configured the credential' do
      described_class::VARS.each { |v| ENV.delete(v) }
      described_class.reload!

      expect(Rails.logger).not_to receive(:warn)
      expect(ApiToken.authenticate('some-wrong-token')).to be_nil
    end
  end
end
