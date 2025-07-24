class CreateWalletConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :wallet_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :address, null: false
      t.string :network, default: 'ethereum'
      t.datetime :last_used_at
      t.timestamps
    end
    
    add_index :wallet_connections, :address, unique: true
  end
end 