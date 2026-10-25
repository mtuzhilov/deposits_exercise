# Per-request context: who is calling and how to correlate the request.
class Current < ActiveSupport::CurrentAttributes
  attribute :api_key, :request_id, :ip_address, :user_agent
end
