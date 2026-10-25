class Tradeline < ApplicationRecord
  include MoneyAttribute

  has_many :deposits, -> { order(:deposit_date, :id) }, dependent: :restrict_with_error, inverse_of: :tradeline

  validates :name, presence: true, length: { maximum: 255 }
  validates_money :amount, greater_than_or_equal_to: 0
  validate :amount_covers_existing_deposits, if: :amount_changed?

  attr_readonly :deposits_total

  # nil when the tradeline has no amount (legacy rows created before the
  # amount validation existed) — we cannot know what is owed.
  def outstanding_balance
    return if amount.nil?

    amount - deposits_total
  end

  # Recomputes the cached total from the deposits table. Used by
  # `bin/rails deposits:reconcile` to detect and repair drift.
  def recalculate_deposits_total!
    actual = deposits.unscope(:order).sum(:amount)
    self.class.where(id: id).update_all(deposits_total: actual, updated_at: Time.current)
    reload
  end

  def deposits_total_drift
    deposits.unscope(:order).sum(:amount) - deposits_total
  end

  private

  def amount_covers_existing_deposits
    return if amount.nil? || deposits_total.nil? || amount >= deposits_total

    errors.add(:amount, "cannot be less than the #{MoneyAttribute.format(deposits_total)} already deposited")
  end
end
