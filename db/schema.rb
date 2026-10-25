# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_10_24_000004) do
  create_table "api_keys", force: :cascade do |t|
    t.string "name", null: false
    t.string "role", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["token_prefix"], name: "index_api_keys_on_token_prefix", unique: true
    t.check_constraint "role IN ('viewer', 'operator', 'admin')", name: "api_keys_role_valid"
  end

  create_table "audit_events", force: :cascade do |t|
    t.integer "api_key_id"
    t.string "action", null: false
    t.string "auditable_type"
    t.integer "auditable_id"
    t.json "metadata", default: {}, null: false
    t.string "request_id"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_audit_events_on_action"
    t.index ["api_key_id"], name: "index_audit_events_on_api_key_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_events_on_auditable"
    t.index ["created_at"], name: "index_audit_events_on_created_at"
    t.index ["request_id"], name: "index_audit_events_on_request_id"
  end

  create_table "deposits", force: :cascade do |t|
    t.integer "tradeline_id", null: false
    t.decimal "amount", precision: 8, scale: 2, null: false
    t.date "deposit_date", null: false
    t.string "idempotency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tradeline_id", "deposit_date", "id"], name: "index_deposits_on_tradeline_id_and_deposit_date_and_id"
    t.index ["tradeline_id", "idempotency_key"], name: "index_deposits_on_tradeline_id_and_idempotency_key", unique: true, where: "idempotency_key IS NOT NULL"
    t.check_constraint "amount > 0", name: "deposits_amount_positive"
  end

  create_table "tradelines", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "amount", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "deposits_total", precision: 8, scale: 2, default: "0.0", null: false
    t.check_constraint "amount IS NULL OR deposits_total <= amount", name: "tradelines_deposits_within_amount"
    t.check_constraint "deposits_total >= 0", name: "tradelines_deposits_total_non_negative"
  end

  add_foreign_key "audit_events", "api_keys"
  add_foreign_key "deposits", "tradelines"
end
