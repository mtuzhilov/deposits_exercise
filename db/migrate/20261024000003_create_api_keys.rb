class CreateApiKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :api_keys do |t|
      t.string :name, null: false
      t.string :role, null: false
      # Only a SHA-256 digest of the token is stored; the prefix identifies
      # a key in logs and listings without revealing the secret.
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :api_keys, :token_digest, unique: true
    add_index :api_keys, :token_prefix, unique: true
    add_check_constraint :api_keys, "role IN ('viewer', 'operator', 'admin')", name: "api_keys_role_valid"
  end
end
