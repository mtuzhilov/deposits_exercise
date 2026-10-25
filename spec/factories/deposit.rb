# frozen_string_literal: true

FactoryBot.define do
  factory :deposit do
    tradeline
    amount { 100 }
    deposit_date { Date.current + 30 }

    # Deposits are normally created through Deposits::Create, which maintains
    # the tradeline's cached total. Keep it consistent when using the factory.
    after(:create) do |deposit|
      Tradeline.where(id: deposit.tradeline_id)
               .update_all(["deposits_total = ROUND(deposits_total + ?, 2)", deposit.amount])
      deposit.tradeline.reload
    end
  end
end
