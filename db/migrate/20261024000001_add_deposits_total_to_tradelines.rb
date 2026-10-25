class AddDepositsTotalToTradelines < ActiveRecord::Migration[7.1]
  def change
    # Running total of deposits, maintained atomically by Deposits::Create.
    # Keeps outstanding balance reads O(1) and lets a single conditional
    # UPDATE enforce "deposits may never exceed the tradeline amount".
    add_column :tradelines, :deposits_total, :decimal, precision: 8, scale: 2, null: false, default: 0

    add_check_constraint :tradelines, "deposits_total >= 0", name: "tradelines_deposits_total_non_negative"
    add_check_constraint :tradelines, "amount IS NULL OR deposits_total <= amount", name: "tradelines_deposits_within_amount"
  end
end
