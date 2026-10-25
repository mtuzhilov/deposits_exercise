class ApplicationController < ActionController::API
  include Pagy::Backend
  include ErrorHandling
  include Authentication
  include Authorization

  # This is a JSON-only API, whatever the client's Accept header says.
  prepend_before_action { request.format = :json }

  private

  def paginate(scope)
    pagy, records = pagy(scope)
    pagy_headers_merge(pagy)
    records
  end

  # Adds the caller to the lograge request line.
  def append_info_to_payload(payload)
    super
    payload[:request_id] = request.request_id
    payload[:ip] = request.remote_ip
    payload[:api_key] = Current.api_key&.token_prefix
    payload[:role] = Current.api_key&.role
  end
end
