require 'rails_helper'

RSpec.describe RefreshToken, type: :model do
  let(:user) { create(:user, login: 'alice') }

  describe '.issue' do
    it 'stores only the hash and returns the raw token once' do
      record, raw = described_class.issue(user: user, ttl: 7.days)

      expect(raw).to be_present
      expect(record.token_hash).to eq(described_class.hash_token(raw))
      expect(record.token_hash).not_to eq(raw)
      expect(record.revoked).to be(false)
      expect(record.expires_at).to be_within(5.seconds).of(7.days.from_now)
    end
  end

  describe '.find_active / .find_any' do
    it 'finds an active token by its raw value' do
      record, raw = described_class.issue(user: user, ttl: 7.days)
      expect(described_class.find_active(raw)).to eq(record)
    end

    it 'does not return revoked or expired tokens from find_active but find_any does' do
      record, raw = described_class.issue(user: user, ttl: 7.days)
      record.update!(revoked: true)

      expect(described_class.find_active(raw)).to be_nil
      expect(described_class.find_any(raw)).to eq(record)
    end

    it 'returns nil for blank or unknown tokens' do
      expect(described_class.find_active(nil)).to be_nil
      expect(described_class.find_active('nope')).to be_nil
    end
  end

  describe '.revoke! / .revoke_all_for!' do
    it 'revokes a single token' do
      _record, raw = described_class.issue(user: user, ttl: 7.days)
      expect(described_class.revoke!(raw)).to be(true)
      expect(described_class.find_active(raw)).to be_nil
    end

    it 'revokes all active tokens for a user and counts them' do
      described_class.issue(user: user, ttl: 7.days)
      described_class.issue(user: user, ttl: 7.days)
      other = create(:user, login: 'bob')
      described_class.issue(user: other, ttl: 7.days)

      expect(described_class.revoke_all_for!(user)).to eq(2)
      expect(described_class.active.where(user_id: user.id)).to be_empty
      expect(described_class.active.where(user_id: other.id).count).to eq(1)
    end
  end

  # The 082 production database has no such table and must never gain one, so the
  # auth controller asks before writing. Both branches are pinned because a check
  # that can only answer "true" would pass here and still 500 on the node it exists for.
  describe '.available?' do
    before { described_class.instance_variable_set(:@available, nil) }

    after { described_class.instance_variable_set(:@available, nil) }

    it 'is true when the table is present, as it is in the test schema' do
      expect(described_class.available?).to be(true)
    end

    it 'is false when the table is absent' do
      allow(described_class.connection).to receive(:table_exists?)
        .with(described_class.table_name).and_return(false)

      expect(described_class.available?).to be(false)
    end

    it 'memoizes, so a login costs no schema query after the first' do
      allow(described_class.connection).to receive(:table_exists?)
        .with(described_class.table_name).and_return(true)

      3.times { described_class.available? }

      expect(described_class.connection).to have_received(:table_exists?).once
    end

    it 'fails closed when the connection itself raises' do
      allow(described_class.connection).to receive(:table_exists?)
        .and_raise(ActiveRecord::StatementInvalid, 'connection lost')

      expect(described_class.available?).to be(false)
    end
  end
end
