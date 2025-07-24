class AddTwoFactorFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :otp_secret_key, :string
    add_column :users, :otp_required_for_login, :boolean, default: false
    add_column :users, :otp_backup_codes, :text
  end
end 