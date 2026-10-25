# Role-based access control. Permissions per role live in ApiKey::PERMISSIONS.
module Authorization
  extend ActiveSupport::Concern

  class_methods do
    def require_permission(permission, **options)
      before_action(**options) { authorize!(permission) }
    end
  end

  private

  def authorize!(permission)
    return if Current.api_key&.can?(permission)

    AuditEvent.record!("authorization.denied", metadata: {
      permission: permission, role: Current.api_key&.role, method: request.method, path: request.path
    })
    render_error(:forbidden, "forbidden", "This API key is not allowed to perform this action")
  end
end
