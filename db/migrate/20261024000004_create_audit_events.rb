class CreateAuditEvents < ActiveRecord::Migration[7.1]
  def change
    # Append-only: rows are never updated or deleted by the application.
    create_table :audit_events do |t|
      t.references :api_key, foreign_key: true
      t.string :action, null: false
      t.references :auditable, polymorphic: true
      t.json :metadata, null: false, default: {}
      t.string :request_id
      t.string :ip_address
      t.string :user_agent
      t.datetime :created_at, null: false
    end

    add_index :audit_events, :action
    add_index :audit_events, :created_at
    add_index :audit_events, :request_id
  end
end
