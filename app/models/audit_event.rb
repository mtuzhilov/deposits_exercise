# Append-only audit trail of security- and money-relevant actions.
class AuditEvent < ApplicationRecord
  ACTIONS = %w[
    tradeline.created
    deposit.created
    deposit.rejected
    deposit.idempotent_replay
    authorization.denied
  ].freeze

  belongs_to :api_key, optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  validates :action, inclusion: { in: ACTIONS }

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "audit events cannot be deleted" }

  def readonly?
    persisted?
  end

  # Records an event, pulling the actor and request details from Current.
  def self.record!(action, auditable: nil, metadata: {})
    create!(
      action: action,
      auditable: auditable,
      metadata: metadata,
      api_key: Current.api_key,
      request_id: Current.request_id,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent&.first(255)
    )
  end
end
