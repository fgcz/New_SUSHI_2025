require 'rails_helper'

# The SEPARATE, ENV-provisioned WRITE credential (082 cutover route B').
#
# Why it is separate rather than a capability flag on the existing credential:
# the existing one is what MCP `prod-082` / sushi-chain presents, i.e. what an
# agent uses to READ production. Promoting that same bearer value to a writer
# would mean that for as long as the cutover window is open, routine agent
# traffic can create rows in the production database. Two credentials keep
# "the MCP key cannot write production" true permanently, and give the
# production rows a distinct `apitoken:<name>` attribution.
#
# Write authority cannot travel through `capabilities`: on the production node
# that column does not exist, so assigning it raises
# ActiveModel::UnknownAttributeError and `effective_capabilities` fail-closes to
# read-only anyway. It travels on a non-database channel instead.
RSpec.describe 'EnvApiToken write credential' do
  let(:read_raw)  { 'fixture-read-bearer-value-not-a-real-token' }
  let(:write_raw) { 'fixture-write-bearer-value-not-a-real-token' }
  let(:read_sha)  { Digest::SHA256.hexdigest(read_raw) }
  let(:write_sha) { Digest::SHA256.hexdigest(write_raw) }

  def configure(read: true,
                write: true,
                write_digest: nil,
                write_scope: '35611',
                write_name: 'cutover-082')
    if read
      ENV[EnvApiToken::DIGEST_VAR] = read_sha
      ENV[EnvApiToken::SCOPE_VAR]  = '35611'
      ENV[EnvApiToken::NAME_VAR]   = 'chain-082'
    end
    if write
      ENV[EnvApiToken::WRITE_DIGEST_VAR] = write_digest || write_sha
      ENV[EnvApiToken::WRITE_SCOPE_VAR]  = write_scope
      ENV[EnvApiToken::WRITE_NAME_VAR]   = write_name
    end
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

  describe 'when only the read credential is configured (082 today)' do
    before { configure(write: false) }

    it 'has no write credential and the read credential still cannot write' do
      expect(EnvApiToken.write_enabled?).to be(false)
      expect(EnvApiToken.write_config).to be_nil

      token = EnvApiToken.token_for(read_raw)
      expect(token.can_write?).to be(false)
      expect(token.name).to eq('chain-082')
    end
  end

  describe 'when both are configured' do
    before { configure }

    it 'authenticates each bearer value as its own credential' do
      read_token  = EnvApiToken.token_for(read_raw)
      write_token = EnvApiToken.token_for(write_raw)

      expect(read_token.name).to eq('chain-082')
      expect(write_token.name).to eq('cutover-082')
    end

    it 'grants write ONLY to the write credential' do
      expect(EnvApiToken.token_for(write_raw).can_write?).to be(true)
      # The whole point of the split: the read credential is unaffected.
      expect(EnvApiToken.token_for(read_raw).can_write?).to be(false)
    end

    it 'never assigns capabilities, so it works where the column does not exist' do
      write_token = EnvApiToken.token_for(write_raw)
      expect(Array(write_token.capabilities)).to eq([])
      # can_write? is true DESPITE effective_capabilities being read-only, which is
      # exactly what makes this work on the production schema.
      expect(write_token.effective_capabilities).to eq(%w[read])
      expect(write_token.can_write?).to be(true)
    end

    it 'is an unsaved, static token that writes nothing to api_tokens' do
      expect { EnvApiToken.token_for(write_raw) }.not_to change(ApiToken, :count)

      token = EnvApiToken.token_for(write_raw)
      expect(token.persisted?).to be(false)
      expect(token.id).to be_nil
      expect(token.principal).to eq('static')
      expect(token.machine?).to be(false)
      expect(token.active?).to be(true)
    end

    it 'carries its own scope, independent of the read credential' do
      configure(write_scope: '1001,2002')
      expect(EnvApiToken.token_for(write_raw).allowed_projects).to eq([1001, 2002])
      expect(EnvApiToken.token_for(read_raw).allowed_projects).to eq([35611])
    end

    it 'refuses any raw value other than the two configured ones' do
      expect(EnvApiToken.token_for('wrong')).to be_nil
      expect(EnvApiToken.token_for(write_sha)).to be_nil # the digest is not the token
    end

    it 'authenticates through ApiToken.authenticate on a DB miss' do
      token = ApiToken.authenticate(write_raw)
      expect(token.name).to eq('cutover-082')
      expect(token.can_write?).to be(true)
    end
  end

  describe 'fail-closed validation of the write credential' do
    it 'rejects a malformed digest and leaves the read credential working' do
      configure(write_digest: 'not-a-digest')

      expect(EnvApiToken.write_config).to be_nil
      expect(EnvApiToken.write_enabled?).to be(false)
      expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_DIGEST_VAR)
      expect(EnvApiToken.token_for(read_raw)).not_to be_nil
      expect(EnvApiToken.token_for(write_raw)).to be_nil
    end

    it 'rejects an absent, empty or non-numeric write scope' do
      ['', ' ', '0', 'p35611', '35611,abc', '-1'].each do |bad|
        configure(write_scope: bad)
        expect(EnvApiToken.write_config).to be_nil
        expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_SCOPE_VAR)
      end
    end

    it 'rejects a write name that could forge a log record or inject into a shell' do
      ["two words", "a;rm -rf /", "new\nline", 'a$(id)', 'x' * 65, '  '].each do |bad|
        configure(write_name: bad)
        expect(EnvApiToken.write_config).to be_nil
        expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_NAME_VAR)
      end
    end

    # Conflating the two credentials is the exact mistake this design exists to
    # prevent, so it is a hard configuration error rather than a silent upgrade of
    # the read credential.
    it 'refuses a write digest identical to the read digest' do
      configure(write_digest: read_sha)

      expect(EnvApiToken.write_config).to be_nil
      expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_DIGEST_VAR)
      # And the read credential must NOT have been promoted as a side effect.
      expect(EnvApiToken.token_for(read_raw).can_write?).to be(false)
    end

    # The name is the only attribution a production row will carry
    # (`apitoken:<name>` in data_sets.user_login / jobs.user). Sharing it would
    # make an agent's read traffic and a human's cutover run indistinguishable
    # after the fact.
    it 'refuses a write name identical to the read name' do
      configure(write_name: 'chain-082')

      expect(EnvApiToken.write_config).to be_nil
      expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_NAME_VAR)
    end

    # MLR round 1, P1 (cited independently by two reviewers). The cross-checks used
    # to run only when BOTH credentials parsed, so an operator who typo'd the READ
    # scope while reusing the read digest as the write digest turned the credential
    # an agent already holds into a writer — the exact outcome route B' exists to
    # prevent, reached by a single typo in a launch script. The comparison must
    # therefore be made on the RAW ENV values, independently of parse success.
    it 'refuses a colliding write digest even when the READ credential is invalid' do
      ENV[EnvApiToken::DIGEST_VAR] = read_sha
      ENV[EnvApiToken::SCOPE_VAR]  = 'p35611' # typo ⇒ read credential invalid
      ENV[EnvApiToken::NAME_VAR]   = 'chain-082'
      ENV[EnvApiToken::WRITE_DIGEST_VAR] = read_sha # reused by mistake
      ENV[EnvApiToken::WRITE_SCOPE_VAR]  = '35611'
      ENV[EnvApiToken::WRITE_NAME_VAR]   = 'cutover-082'
      EnvApiToken.reload!

      expect(EnvApiToken.write_config).to be_nil
      expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_DIGEST_VAR)
      # The bearer the agent already holds must not have become a writer.
      expect(EnvApiToken.token_for(read_raw)).to be_nil
    end

    it 'refuses a colliding write name even when the READ credential is invalid' do
      ENV[EnvApiToken::DIGEST_VAR] = read_sha
      ENV[EnvApiToken::SCOPE_VAR]  = 'p35611' # typo ⇒ read credential invalid
      ENV[EnvApiToken::NAME_VAR]   = 'chain-082'
      ENV[EnvApiToken::WRITE_DIGEST_VAR] = write_sha
      ENV[EnvApiToken::WRITE_SCOPE_VAR]  = '35611'
      ENV[EnvApiToken::WRITE_NAME_VAR]   = 'chain-082' # shared attribution
      EnvApiToken.reload!

      expect(EnvApiToken.write_config).to be_nil
      expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_NAME_VAR)
    end

    # MLR round 1, P2 — pre-existing in the single-credential version: every field
    # matched /\A\d+\z/, then `select(&:positive?)` silently DROPPED a zero, so
    # "0,1" quietly became scope [1] instead of being refused. A scope is authority;
    # narrowing it silently is the wrong direction for a fail-closed parser.
    it 'refuses a scope containing a non-positive field rather than dropping it' do
      ['0,1', '1,0', '0,0'].each do |bad|
        configure(write_scope: bad)
        expect(EnvApiToken.write_config).to be_nil
        expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_SCOPE_VAR)
      end
    end

    # MLR round 2, P2 — the same leniency one step further: an EMPTY field was
    # dropped as well, so "1,,2" quietly meant [1, 2] and ",1" meant [1].
    it 'refuses a scope containing an empty field rather than dropping it' do
      ['1,,2', ',1', '1,', ',', '35611,,'].each do |bad|
        configure(write_scope: bad)
        expect(EnvApiToken.write_config).to be_nil
        expect(EnvApiToken.errors.join).to include(EnvApiToken::WRITE_SCOPE_VAR)
      end
    end

    it 'still tolerates surrounding whitespace in a well-formed list' do
      configure(write_scope: ' 35611 , 1001 ')
      expect(EnvApiToken.write_config.scope).to eq([35611, 1001])
    end

    it 'reports intent when only the write variables are set, so a typo is not silent' do
      configure(read: false, write_digest: 'garbage')
      expect(EnvApiToken.intended?).to be(true)
      expect(EnvApiToken.enabled?).to be(false)
      expect(EnvApiToken.write_enabled?).to be(false)
    end

    it 'treats a write digest with no write scope as a misconfiguration' do
      ENV[EnvApiToken::WRITE_DIGEST_VAR] = write_sha
      EnvApiToken.reload!
      expect(EnvApiToken.write_config).to be_nil
    end
  end

  describe 'a write credential without a read credential' do
    before { configure(read: false) }

    it 'is allowed and works on its own' do
      expect(EnvApiToken.enabled?).to be(false)
      expect(EnvApiToken.write_enabled?).to be(true)
      expect(EnvApiToken.token_for(write_raw).can_write?).to be(true)
    end
  end

  describe 'immutability' do
    before { configure }

    it 'ignores ENV changes made after parsing' do
      ENV[EnvApiToken::WRITE_DIGEST_VAR] = Digest::SHA256.hexdigest('an-attackers-token')
      expect(EnvApiToken.token_for('an-attackers-token')).to be_nil
      expect(EnvApiToken.token_for(write_raw).can_write?).to be(true)
    end

    it 'freezes the write scope so no caller can widen it in place' do
      EnvApiToken.token_for(write_raw).scope << 999
      expect(EnvApiToken.write_config.scope).to eq([35611]).and be_frozen
      expect(EnvApiToken.token_for(write_raw).allowed_projects).to eq([35611])
    end
  end

  # The write channel must not be reachable from a database row: a DB token's
  # authority stays governed by `capabilities` alone.
  describe 'ApiToken#can_write? for everything else' do
    it 'is unchanged for a DB token with no capabilities recorded' do
      _raw, token = ApiToken.issue(name: 'reg', scope: [1001])
      expect(token.can_write?).to be(false)
    end

    it 'is unchanged for a DB token granted write' do
      _raw, token = ApiToken.issue(name: 'reg', scope: [1001], capabilities: %w[read write])
      expect(token.can_write?).to be(true)
    end

    it 'defaults to read-only and is granted only by the explicit grant' do
      token = ApiToken.new(name: 'x', principal: 'static', scope: [1])
      expect(token.env_write_granted?).to be(false)
      expect(token.can_write?).to be(false)

      token.grant_env_write!
      expect(token.env_write_granted?).to be(true)
      expect(token.can_write?).to be(true)
    end

    # MLR round 1, P3: with an attr_writer, an attributes hash carrying
    # `env_write_granted: true` would have been silently accepted. A no-argument
    # bang method has no assignment surface at all, so the same hash RAISES —
    # which is what makes "no request parameter can promote a token" a property of
    # the code rather than of the current call sites.
    it 'cannot be granted through an attributes hash' do
      expect {
        ApiToken.new(name: 'x', principal: 'static', scope: [1], env_write_granted: true)
      }.to raise_error(ActiveModel::UnknownAttributeError)
    end

    # MLR round 2, P3 (two reviewers): the grant has to stay public for EnvApiToken
    # to call it, so "only EnvApiToken grants this" was a claim about call sites.
    # Refusing a persisted record makes the dangerous half structural — a row from
    # `api_tokens`, whose authority belongs to `capabilities`, cannot be promoted
    # in-process by anyone.
    it 'refuses to promote a PERSISTED token, whatever calls it' do
      _raw, db_token = ApiToken.issue(name: 'reg', scope: [1001])

      expect { db_token.grant_env_write! }.to raise_error(ArgumentError, /never saved/)
      expect(db_token.can_write?).to be(false)
    end
  end
end
