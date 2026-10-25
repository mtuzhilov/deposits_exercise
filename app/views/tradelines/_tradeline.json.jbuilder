json.extract! tradeline, :id, :name
json.amount MoneyAttribute.format(tradeline.amount)
json.deposits_total MoneyAttribute.format(tradeline.deposits_total)
json.outstanding_balance MoneyAttribute.format(tradeline.outstanding_balance)
json.extract! tradeline, :created_at, :updated_at
