# Request throttling. Limits are per process when using the in-memory store;
# in production with several processes, point Rack::Attack.cache.store at Redis.
class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  PERIOD = 60 # seconds

  def self.bearer_token(req)
    req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer\s+(.+)\z/i, 1]
  end

  safelist("health check") { |req| req.path == "/up" }

  # Each API key gets its own budget. Keyed by a digest so tokens never sit in the cache.
  throttle("requests per api key", limit: ENV.fetch("RATE_LIMIT_PER_KEY", 300).to_i, period: PERIOD) do |req|
    token = bearer_token(req)
    ApiKey.digest(token) if token
  end

  # Requests without credentials always fail, so allow very few: this slows
  # down anyone scanning the API.
  throttle("unauthenticated requests per ip", limit: ENV.fetch("RATE_LIMIT_UNAUTHENTICATED", 20).to_i,
                                              period: PERIOD) do |req|
    req.ip unless bearer_token(req)
  end

  # Upper bound per client IP regardless of how many keys it cycles through.
  throttle("requests per ip", limit: ENV.fetch("RATE_LIMIT_PER_IP", 1000).to_i, period: PERIOD, &:ip)

  self.throttled_responder = lambda do |request|
    match = request.env["rack.attack.match_data"] || {}
    period = match[:period] || PERIOD
    retry_after = (period - (Time.now.to_i % period)).to_s
    body = { error: { code: "rate_limited", message: "Too many requests, retry after #{retry_after} seconds" } }
    [429, { "content-type" => "application/json", "retry-after" => retry_after }, [body.to_json]]
  end
end

# Tests opt in explicitly (see spec/requests/rate_limiting_spec.rb).
Rack::Attack.enabled = !Rails.env.test?
