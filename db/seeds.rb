# Idempotent sample data for local development and the README walkthrough.

[
  { name: "Visa Platinum Credit Card", amount: "3223.54" },
  { name: "Auto Loan", amount: "18500.00" },
  { name: "Personal Loan", amount: "5000.00" }
].each do |attrs|
  Tradeline.find_or_create_by!(name: attrs[:name]) { |t| t.amount = attrs[:amount] }
end
puts "Tradelines: #{Tradeline.count}"

# Development-only API keys, one per role. Tokens are only knowable at
# creation, so seeding again issues fresh keys and revokes the old seed keys.
if Rails.env.development?
  ApiKey.where("name LIKE ?", "dev-seed-%").find_each(&:revoke!)
  puts "\nDevelopment API keys (shown once):"
  ApiKey::ROLES.each do |role|
    _key, token = ApiKey.issue!(name: "dev-seed-#{role}", role: role)
    puts "  export #{role.upcase}_TOKEN=#{token}"
  end
end
