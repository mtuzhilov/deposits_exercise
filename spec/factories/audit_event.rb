# frozen_string_literal: true

FactoryBot.define do
  factory :audit_event do
    action { "deposit.created" }
    metadata { {} }
  end
end
