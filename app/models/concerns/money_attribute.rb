# Validations shared by every money column (decimal precision 8, scale 2).
#
# Rails rounds decimal input to the column scale on assignment, so 10.005
# would silently become 10.01. For money we reject such input instead, which
# means inspecting the raw value before type casting.
module MoneyAttribute
  extend ActiveSupport::Concern

  MAX_AMOUNT = BigDecimal("999999.99")

  # Money is serialized as a string with exactly 2 decimals ("3000.00") so
  # clients never parse it into a lossy float.
  def self.format(value)
    value&.to_d&.round(2)&.then { |d| ActiveSupport::NumberHelper.number_to_rounded(d, precision: 2) }
  end

  class_methods do
    def validates_money(attribute, allow_nil: false, **bounds)
      validates attribute, presence: true unless allow_nil
      validates attribute, numericality: { less_than_or_equal_to: MAX_AMOUNT, allow_nil: true, **bounds }
      validate { validate_money_scale(attribute) }
    end
  end

  private

  def validate_money_scale(attribute)
    raw = read_attribute_before_type_cast(attribute)
    value = BigDecimal(raw.to_s.strip, exception: false) unless raw.nil?
    return if value.nil? || value == value.round(2)

    errors.add(attribute, "must have at most 2 decimal places")
  end
end
