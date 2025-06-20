class AddDeviseFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email, :string, null: true
    add_column :users, :encrypted_password, :string, null: true
    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    
    # Update existing users to have unique emails based on login
    reversible do |dir|
      dir.up do
        execute "UPDATE users SET email = login || '@example.com' WHERE email IS NULL OR email = ''"
        execute "UPDATE users SET encrypted_password = '' WHERE encrypted_password IS NULL"
      end
    end
    
    # Now make email and encrypted_password not null
    change_column_null :users, :email, false
    change_column_null :users, :encrypted_password, false
    
    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
  end
end
