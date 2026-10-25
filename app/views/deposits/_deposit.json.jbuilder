json.extract! deposit, :id, :tradeline_id
json.amount MoneyAttribute.format(deposit.amount)
json.extract! deposit, :deposit_date, :created_at
