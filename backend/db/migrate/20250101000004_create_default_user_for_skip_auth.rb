class CreateDefaultUserForSkipAuth < ActiveRecord::Migration[8.0]
  def up
    # Create a default user for when authentication is skipped
    # Skip validation since we're creating a dummy user for skip auth mode
    user = User.new(
      login: 'anonymous',
      email: 'anonymous@example.com',
      encrypted_password: '$2a$12$dummy.hash.for.skip.auth',
      created_at: Time.current,
      updated_at: Time.current
    )
    user.save!(validate: false) unless User.exists?(login: 'anonymous')
  end

  def down
    User.where(login: 'anonymous').destroy_all
  end
end 