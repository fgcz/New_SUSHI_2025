require 'digest'
require 'securerandom'

# Opaque refresh tokens for the JWT auth gateway (B2).
#
# Parity with Ronald's FastAPI implementation
# (rdom_test_new_sushi_20251030/backend_python/app/repositories/refresh_token.py):
# the raw token is a cryptographically random string handed to the client in an
# HttpOnly cookie; only its SHA-256 hash is persisted. B2 additionally performs
# rotation + reuse detection in Api::V1::AuthController#refresh.
class RefreshToken < ApplicationRecord
  belongs_to :user

  # Active = not revoked and not expired.
  scope :active, -> { where(revoked: false).where('expires_at > ?', Time.current) }

  # Is this table actually present in the database we are connected to?
  #
  # 082's database IS legacy production SUSHI's, which has no `refresh_tokens`
  # table and must never gain one — no migration runs on that node, by standing
  # decision. Without this check a successful login there raises
  # ActiveRecord::StatementInvalid on the INSERT and answers 500, so LDAP could
  # not be exercised on the production node at all.
  #
  # Memoized per process: a login must not cost a schema query, and the answer
  # cannot change while the process lives. Rails' reloader resets the class in
  # development, which re-asks — that is the behaviour we want after a migration.
  def self.available?
    return @available unless @available.nil?

    @available = connection.table_exists?(table_name)
  rescue StandardError => e
    Rails.logger.error("RefreshToken.available? check failed: #{e.message}")
    @available = false
  end

  # SHA-256 hex digest used as the at-rest representation of a raw token.
  def self.hash_token(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  # Issue a new refresh token for +user+, valid for +ttl+.
  # Returns [record, raw_token]; the raw token is only available here (never stored).
  def self.issue(user:, ttl:)
    raw = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_hash: hash_token(raw),
      expires_at: ttl.from_now,
      revoked: false
    )
    [record, raw]
  end

  # Lookup a valid (non-revoked, non-expired) token by its raw value.
  def self.find_active(raw)
    return nil if raw.blank?

    active.find_by(token_hash: hash_token(raw))
  end

  # Lookup by raw value regardless of revoked/expired state (for reuse detection).
  def self.find_any(raw)
    return nil if raw.blank?

    find_by(token_hash: hash_token(raw))
  end

  # Revoke a single token by its raw value. Returns true if a token was revoked.
  def self.revoke!(raw)
    record = find_any(raw)
    return false unless record

    record.update!(revoked: true) unless record.revoked?
    true
  end

  # Revoke every active token for +user+. Returns the number revoked.
  def self.revoke_all_for!(user)
    active.where(user_id: user.id).update_all(revoked: true, updated_at: Time.current)
  end
end
