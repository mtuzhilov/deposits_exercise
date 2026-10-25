# Every request must carry `Authorization: Bearer <api key>`.
module Authentication
  extend ActiveSupport::Concern

  included do
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :set_request_context, :authenticate!
  end

  private

  def set_request_context
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end

  def authenticate!
    api_key = authenticate_with_http_token { |token, _options| ApiKey.authenticate(token) }
    return render_unauthorized unless api_key

    api_key.touch_last_used!
    Current.api_key = api_key
  end

  # Deliberately generic: do not reveal whether a key exists, expired or was revoked.
  def render_unauthorized
    response.headers["WWW-Authenticate"] = %(Bearer realm="deposits")
    render_error(:unauthorized, "unauthorized", "A valid API key is required")
  end
end
