json.partial! "deposits/deposit", deposit: @deposit
json.tradeline_outstanding_balance MoneyAttribute.format(@tradeline.outstanding_balance)
