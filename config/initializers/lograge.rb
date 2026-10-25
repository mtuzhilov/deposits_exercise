# One structured JSON line per request instead of Rails' multi-line logs.
# The caller's API key prefix and role are added in
# ApplicationController#append_info_to_payload. The Authorization header and
# token values are never logged.
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    event.payload.slice(:request_id, :ip, :api_key, :role).merge(time: Time.current.utc.iso8601(3))
  end
end
