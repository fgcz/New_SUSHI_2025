class CreateDefaultUserForSkipAuth < ActiveRecord::Migration[8.0]
  def up
    # Skip if users table doesn't have required columns yet (run order safety)
    return unless table_exists?(:users)
    return unless column_exists?(:users, :login)
    # email/encrypted_password may not exist yet depending on migration order
    has_email = column_exists?(:users, :email)
    has_encrypted = column_exists?(:users, :encrypted_password)

    # Create a default user for when authentication is skipped
    # Skip validation since we're creating a dummy user for skip auth mode
    attrs = { login: 'anonymous', created_at: Time.current, updated_at: Time.current }
    attrs[:email] = 'anonymous@example.com' if has_email
    attrs[:encrypted_password] = '$2a$12$dummy.hash.for.skip.auth' if has_encrypted

    user = User.new(attrs)
    user.save!(validate: false) unless User.exists?(login: 'anonymous')
  end

  def down
    User.where(login: 'anonymous').destroy_all
  end
end 