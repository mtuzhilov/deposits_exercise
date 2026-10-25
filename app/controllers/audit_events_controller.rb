class AuditEventsController < ApplicationController
  # Query param => column. `event` rather than `action`, which Rails reserves
  # for the controller action name.
  FILTERS = {
    event: :action,
    auditable_type: :auditable_type,
    auditable_id: :auditable_id,
    api_key_id: :api_key_id,
    request_id: :request_id
  }.freeze

  require_permission :read_audit_events

  def index
    scope = AuditEvent.includes(:api_key).order(id: :desc)
    FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    @audit_events = paginate(scope)
  end
end
