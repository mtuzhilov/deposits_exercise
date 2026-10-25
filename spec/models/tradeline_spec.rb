require 'rails_helper'

RSpec.describe Tradeline, type: :model do
  subject(:tradeline) { build(:tradeline) }

  describe 'associations' do
    it { is_expected.to have_many(:deposits).dependent(:restrict_with_error) }

    it 'orders deposits by date, then id' do
      tradeline.save!
      later = create(:deposit, tradeline: tradeline, deposit_date: Date.new(2027, 1, 1))
      earlier = create(:deposit, tradeline: tradeline, deposit_date: Date.new(2026, 12, 1))
      expect(tradeline.reload.deposits).to eq([earlier, later])
    end

    it 'cannot be destroyed while it has deposits' do
      deposit = create(:deposit)
      expect(deposit.tradeline.destroy).to be(false)
      expect(deposit.tradeline.errors[:base]).to include(/dependent deposits exist/)
    end
  end

  describe 'validations' do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_presence_of(:amount) }

    it 'accepts zero' do
      tradeline.amount = 0
      expect(tradeline).to be_valid
    end

    it 'rejects a negative amount' do
      tradeline.amount = -1
      expect(tradeline).not_to be_valid
      expect(tradeline.errors[:amount]).to include('must be greater than or equal to 0')
    end

    it 'rejects an amount larger than the column can hold' do
      tradeline.amount = '1000000.00'
      expect(tradeline).not_to be_valid
      expect(tradeline.errors[:amount]).to include('must be less than or equal to 999999.99')
    end

    it 'rejects a non-numeric amount' do
      tradeline.amount = 'lots'
      expect(tradeline).not_to be_valid
      expect(tradeline.errors[:amount]).to include('is not a number')
    end

    it 'rejects more than 2 decimal places instead of silently rounding' do
      tradeline.amount = '10.005'
      expect(tradeline).not_to be_valid
      expect(tradeline.errors[:amount]).to include('must have at most 2 decimal places')
    end

    it 'accepts trailing zeros' do
      tradeline.amount = '10.500'
      expect(tradeline).to be_valid
    end

    it 'cannot lower the amount below what has already been deposited' do
      deposit = create(:deposit, amount: 500)
      tradeline = deposit.tradeline
      tradeline.amount = 499.99
      expect(tradeline).not_to be_valid
      expect(tradeline.errors[:amount]).to include('cannot be less than the 500.00 already deposited')
    end
  end

  describe '#outstanding_balance' do
    it 'is the amount minus all deposits' do
      tradeline = create(:tradeline, amount: '1000.00')
      create(:deposit, tradeline: tradeline, amount: '250.25')
      create(:deposit, tradeline: tradeline, amount: '100.10')
      expect(tradeline.reload.outstanding_balance).to eq(BigDecimal('649.65'))
    end

    it 'is the full amount when there are no deposits' do
      expect(build(:tradeline, amount: '3223.54').outstanding_balance).to eq(BigDecimal('3223.54'))
    end

    it 'is nil for a legacy tradeline without an amount' do
      tradeline = build(:tradeline, amount: nil)
      tradeline.save!(validate: false)
      expect(tradeline.outstanding_balance).to be_nil
    end
  end

  describe 'database constraints' do
    let(:tradeline) { create(:tradeline, amount: 100) }

    it 'prevents deposits_total exceeding the amount' do
      expect { described_class.where(id: tradeline.id).update_all(deposits_total: 100.01) }
        .to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/)
    end

    it 'prevents a negative deposits_total' do
      expect { described_class.where(id: tradeline.id).update_all(deposits_total: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/)
    end
  end

  describe 'reconciliation' do
    let(:tradeline) { create(:tradeline, amount: 1000) }

    before do
      create(:deposit, tradeline: tradeline, amount: 300)
      described_class.where(id: tradeline.id).update_all(deposits_total: 250)
      tradeline.reload
    end

    it 'reports drift between the cached total and the deposits' do
      expect(tradeline.deposits_total_drift).to eq(50)
    end

    it 'repairs the cached total' do
      tradeline.recalculate_deposits_total!
      expect(tradeline.deposits_total).to eq(300)
      expect(tradeline.deposits_total_drift).to eq(0)
    end
  end
end
