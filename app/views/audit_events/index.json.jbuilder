json.array! @audit_events do |event|
  json.extract! event, :id, :action, :auditable_type, :auditable_id, :metadata, :request_id, :ip_address,
                :user_agent, :created_at
  json.actor do
    if event.api_key
      json.extract! event.api_key, :id, :name, :role, :token_prefix
    else
      json.nil!
    end
  end
end
