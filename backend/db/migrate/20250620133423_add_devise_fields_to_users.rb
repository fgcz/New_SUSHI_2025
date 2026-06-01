class AddDeviseFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    # Only add columns if they don't already exist (handles partial migration failures)
    add_column :users, :email, :string, null: true unless column_exists?(:users, :email)
    add_column :users, :encrypted_password, :string, null: true unless column_exists?(:users, :encrypted_password)
    add_column :users, :reset_password_token, :string unless column_exists?(:users, :reset_password_token)
    add_column :users, :reset_password_sent_at, :datetime unless column_exists?(:users, :reset_password_sent_at)
    
    # Update existing users to have unique emails based on login
    reversible do |dir|
      dir.up do
        execute "UPDATE users SET email = CONCAT(login, '@example.com') WHERE email IS NULL OR email = ''"
        execute "UPDATE users SET encrypted_password = '' WHERE encrypted_password IS NULL"
      end
    end
    
    # Now make email and encrypted_password not null
    change_column_null :users, :email, false
    change_column_null :users, :encrypted_password, false
    
    add_index :users, :email, unique: true unless index_exists?(:users, :email)
    add_index :users, :reset_password_token, unique: true unless index_exists?(:users, :reset_password_token)
  end
end
