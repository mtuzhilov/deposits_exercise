class Deposit < ApplicationRecord
  include MoneyAttribute

  ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/

  belongs_to :tradeline, inverse_of: :deposits

  validates_money :amount, greater_than: 0
  validates :deposit_date, presence: true
  validate :deposit_date_is_iso8601
  validates :idempotency_key, length: { maximum: 255 }, allow_nil: true

  # Deposits are financial records: once written they are never edited.
  # Corrections should be modelled as new (reversing) entries.
  def readonly?
    persisted?
  end

  private

  # Rails casts unparseable dates ("2026-13-45") to nil, which would surface as
  # a misleading "can't be blank", and leniently parses formats like
  # "Oct 24 2026" or "24/10/2026" whose meaning is ambiguous. Require ISO 8601.
  def deposit_date_is_iso8601
    raw = read_attribute_before_type_cast(:deposit_date)
    return if raw.blank? || raw.is_a?(Date)
    return if raw.is_a?(String) && raw.match?(ISO_DATE) && deposit_date.present?

    errors.delete(:deposit_date)
    errors.add(:deposit_date, "must be a valid date in YYYY-MM-DD format")
  end
end
