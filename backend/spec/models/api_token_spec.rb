require 'rails_helper'

RSpec.describe ApiToken, type: :model do
  describe '.issue' do
    context 'static principal' do
      it 'issues a static token with a scope and returns [raw, record]' do
        raw, token = ApiToken.issue(name: 'reg', scope: [1001, 2002])
        expect(raw).to be_present
        expect(token.principal).to eq('static')
        expect(token.scope).to eq([1001, 2002])
        expect(token.login).to be_nil
        expect(token.expires_at).to be_nil
      end

      it 'requires a non-empty scope' do
        expect { ApiToken.issue(name: 'reg', scope: []) }
          .to raise_error(ArgumentError, /scope is required/)
      end
    end

    context 'user principal' do
      it 'issues a user token bound to a login with a bounded TTL' do
        raw, token = ApiToken.issue(name: 'u', principal: 'user', login: 'masaomi', ttl_days: 90)
        expect(raw).to be_present
        expect(token.principal).to eq('user')
        expect(token.login).to eq('masaomi')
        expect(token.scope).to eq([])
        expect(token.expires_at).to be_within(1.minute).of(Time.now + 90.days)
      end

      it 'requires a login' do
        expect { ApiToken.issue(name: 'u', principal: 'user', login: ' ', ttl_days: 30) }
          .to raise_error(ArgumentError, /login is required/)
      end

      it 'requires a TTL' do
        expect { ApiToken.issue(name: 'u', principal: 'user', login: 'x') }
          .to raise_error(ArgumentError, /requires TTL_DAYS/)
      end

      it 'rejects a non-integer TTL' do
        expect { ApiToken.issue(name: 'u', principal: 'user', login: 'x', ttl_days: '90abc') }
          .to raise_error(ArgumentError, /positive integer/)
      end

      it 'rejects a TTL over the maximum' do
        expect { ApiToken.issue(name: 'u', principal: 'user', login: 'x', ttl_days: 91) }
          .to raise_error(ArgumentError, /between 1 and 90/)
      end
    end

    context 'machine principal' do
      it 'issues an unscoped, login-less machine token' do
        _raw, token = ApiToken.issue(name: 'job_manager', principal: 'machine')
        expect(token.principal).to eq('machine')
        expect(token.machine?).to be(true)
        expect(token.static?).to be(false)
        expect(token.user?).to be(false)
        expect(token.scope).to eq([])
        expect(token.login).to be_nil
      end

      it 'ignores any scope passed and is active with no expiry' do
        _raw, token = ApiToken.issue(name: 'jm', principal: 'machine', scope: [1001])
        expect(token.scope).to eq([])
        expect(token.active?).to be(true)
      end
    end

    it 'rejects an unknown principal' do
      expect { ApiToken.issue(name: 'x', principal: 'root', scope: [1]) }
        .to raise_error(ArgumentError, /unknown principal/)
    end

    it 'stores only a salted hash, never the raw token' do
      raw, token = ApiToken.issue(name: 'reg', scope: [1001])
      expect(token.token_hash).not_to eq(raw)
      expect(token.token_hash).to eq(ApiToken.digest(raw))
      expect(ApiToken.digest(raw)).to eq(Digest::SHA256.hexdigest(ApiToken.salt + raw))
    end
  end

  describe '.authenticate' do
    it 'returns the token for a valid raw value' do
      raw, token = ApiToken.issue(name: 'reg', scope: [1001])
      expect(ApiToken.authenticate(raw)).to eq(token)
    end

    it 'is fail-closed for blank/unknown/expired/revoked tokens' do
      expect(ApiToken.authenticate('')).to be_nil
      expect(ApiToken.authenticate('nope')).to be_nil

      raw_exp, expired = ApiToken.issue(name: 'e', scope: [1])
      expired.update!(expires_at: 1.day.ago)
      expect(ApiToken.authenticate(raw_exp)).to be_nil

      raw_rev, revoked = ApiToken.issue(name: 'r', scope: [1])
      revoked.update!(revoked_at: Time.now)
      expect(ApiToken.authenticate(raw_rev)).to be_nil
    end
  end

  describe '#active?' do
    it 'is false for a user token with a nil expiry (defense in depth)' do
      _raw, token = ApiToken.issue(name: 'u', principal: 'user', login: 'x', ttl_days: 30)
      token.update_column(:expires_at, nil)
      expect(token.active?).to be(false)
    end
  end

  describe '#in_scope?' do
    it 'tests membership against the stored scope (static)' do
      _raw, token = ApiToken.issue(name: 'reg', scope: [1001, 2002])
      expect(token.in_scope?(1001)).to be(true)
      expect(token.in_scope?(3003)).to be(false)
    end
  end

  describe '#allowed_projects' do
    it 'returns the stored scope for a static token' do
      _raw, token = ApiToken.issue(name: 'reg', scope: [1001, 2002])
      expect(token.allowed_projects).to eq([1001, 2002])
    end

    it 'resolves live FGCZ membership for a user token' do
      _raw, token = ApiToken.issue(name: 'u', principal: 'user', login: 'masaomi', ttl_days: 30)
      allow(FGCZ).to receive(:get_user_projects2).with('masaomi').and_return(['p1001', 'p2002'])
      expect(token.allowed_projects).to eq([1001, 2002])
    end

    it 'raises ResolverUnavailable when the resolver call fails' do
      _raw, token = ApiToken.issue(name: 'u', principal: 'user', login: 'masaomi', ttl_days: 30)
      allow(FGCZ).to receive(:get_user_projects2).and_raise(StandardError, 'ldap down')
      expect { token.allowed_projects }.to raise_error(ApiToken::ResolverUnavailable)
    end
  end

  # Write authority is orthogonal to project scope. Before this existed, a token's authority
  # was "which projects" only, and the /v1 endpoint allowlist restricted USER principals
  # while static ones passed unconditionally — so a long-lived service credential outranked
  # a person's token. The production instance was safe only because it ran wholly read-only;
  # flipping the write policy to `additive` would otherwise promote every in-scope token,
  # including the read-only MCP credential, into a job submitter.
  describe 'capabilities' do
    it 'defaults to read-only when none are given' do
      _raw, token = ApiToken.issue(name: 'ro', scope: [1001])
      expect(token.effective_capabilities).to eq(['read'])
      expect(token.can_write?).to be false
    end

    it 'treats a token predating the column (NULL) as read-only' do
      _raw, token = ApiToken.issue(name: 'legacy', scope: [1001])
      token.update_column(:capabilities, nil)
      expect(token.reload.effective_capabilities).to eq(['read'])
      expect(token.can_write?).to be false
    end

    it 'grants write when asked for' do
      _raw, token = ApiToken.issue(name: 'rw', scope: [1001], capabilities: %w[read write])
      expect(token.can_write?).to be true
    end

    it 'implies read for a write-only request, so it cannot change what it cannot see' do
      _raw, token = ApiToken.issue(name: 'w', scope: [1001], capabilities: ['write'])
      expect(token.effective_capabilities).to contain_exactly('read', 'write')
    end

    it 'rejects an unknown capability instead of ignoring the typo' do
      expect { ApiToken.issue(name: 'x', scope: [1001], capabilities: ['wirte']) }
        .to raise_error(ArgumentError, /unknown capabilities/)
    end

    it 'exempts the machine principal (the /internal job_manager bridge)' do
      _raw, token = ApiToken.issue(name: 'jm', principal: 'machine')
      expect(token.can_write?).to be true
    end

    it 'is case- and whitespace-insensitive' do
      _raw, token = ApiToken.issue(name: 'rw', scope: [1001], capabilities: [' Write '])
      expect(token.can_write?).to be true
    end
  end
end
