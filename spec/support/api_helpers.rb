module ApiHelpers
  def auth_headers(role = :admin)
    _key, token = ApiKey.issue!(name: "spec-#{role}", role: role)
    { "Authorization" => "Bearer #{token}" }
  end

  def json_headers(role = :admin)
    auth_headers(role).merge("Content-Type" => "application/json", "Accept" => "application/json")
  end

  def json
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
  config.include ApiHelpers, type: :controller
end
