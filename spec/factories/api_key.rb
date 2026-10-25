# frozen_string_literal: true

FactoryBot.define do
  factory :api_key do
    sequence(:name) { |n| "client-#{n}" }
    role { "viewer" }
    token_digest { ApiKey.digest("#{ApiKey::TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}") }
    sequence(:token_prefix) { |n| format("dpx_%08d", n) }
  end
end
