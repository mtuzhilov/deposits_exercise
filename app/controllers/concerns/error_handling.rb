# Renders every error as { "error": { "code", "message", "details"? } }.
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do |e|
      render_error(:not_found, "not_found", "#{e.model || 'Record'} not found")
    end

    rescue_from ActionController::ParameterMissing do |e|
      render_error(:bad_request, "bad_request", "Missing required parameter: #{e.param}")
    end

    rescue_from ActionDispatch::Http::Parameters::ParseError do
      render_error(:bad_request, "bad_request", "Request body is not valid JSON")
    end

    rescue_from Pagy::VariableError do |e|
      render_error(:bad_request, "bad_request", "Invalid pagination parameter: #{e.variable}")
    end
  end

  private

  def render_error(status, code, message, details = nil)
    error = { code: code, message: message }
    error[:details] = details if details.present?
    render json: { error: error }, status: status
  end

  def render_validation_errors(record)
    render_error(:unprocessable_entity, "validation_failed", "#{record.class.model_name.human} is invalid",
                 record.errors.to_hash)
  end
end
