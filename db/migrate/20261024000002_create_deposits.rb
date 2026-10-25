class CreateDeposits < ActiveRecord::Migration[7.1]
  def change
    create_table :deposits do |t|
      t.references :tradeline, null: false, foreign_key: true, index: false
      t.decimal :amount, precision: 8, scale: 2, null: false
      t.date :deposit_date, null: false
      t.string :idempotency_key
      t.timestamps
    end

    add_index :deposits, %i[tradeline_id deposit_date id]
    add_index :deposits, %i[tradeline_id idempotency_key], unique: true, where: "idempotency_key IS NOT NULL"
    add_check_constraint :deposits, "amount > 0", name: "deposits_amount_positive"
  end
end
