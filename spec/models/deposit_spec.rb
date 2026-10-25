require 'rails_helper'

RSpec.describe Deposit, type: :model do
  subject(:deposit) { build(:deposit) }

  it { is_expected.to belong_to(:tradeline) }
  it { is_expected.to be_valid }

  describe 'amount' do
    it { is_expected.to validate_presence_of(:amount) }

    it 'accepts a numeric string with 2 decimals' do
      deposit.amount = '12.34'
      expect(deposit).to be_valid
    end

    it 'accepts a whole number' do
      deposit.amount = 12
      expect(deposit).to be_valid
    end

    it 'accepts the smallest unit of currency' do
      deposit.amount = '0.01'
      expect(deposit).to be_valid
    end

    [0, '0.00', -5, '-0.01'].each do |value|
      it "rejects #{value.inspect}" do
        deposit.amount = value
        expect(deposit).not_to be_valid
        expect(deposit.errors[:amount]).to include('must be greater than 0')
      end
    end

    it 'rejects non-numeric input' do
      deposit.amount = '12abc'
      expect(deposit).not_to be_valid
      expect(deposit.errors[:amount]).to include('is not a number')
    end

    it 'rejects fractions of a cent given as a string' do
      deposit.amount = '1.005'
      expect(deposit).not_to be_valid
      expect(deposit.errors[:amount]).to include('must have at most 2 decimal places')
    end

    it 'rejects fractions of a cent given as a JSON number' do
      deposit.amount = 1.005
      expect(deposit).not_to be_valid
      expect(deposit.errors[:amount]).to include('must have at most 2 decimal places')
    end

    it 'rejects amounts larger than the column can hold' do
      deposit.amount = '1000000'
      expect(deposit).not_to be_valid
      expect(deposit.errors[:amount]).to include('must be less than or equal to 999999.99')
    end
  end

  describe 'deposit_date' do
    it { is_expected.to validate_presence_of(:deposit_date) }

    it 'accepts a future ISO 8601 date' do
      deposit.deposit_date = (Date.current + 90).iso8601
      expect(deposit).to be_valid
    end

    it 'accepts a past date (backdated deposits are allowed)' do
      deposit.deposit_date = '2020-01-15'
      expect(deposit).to be_valid
    end

    it 'accepts a Date object' do
      deposit.deposit_date = Date.new(2027, 3, 1)
      expect(deposit).to be_valid
    end

    ['2026-13-45', '2026-02-30', 'tomorrow', '10/24/2026', 'Oct 24 2026', '2026-1-5', 20_261_024].each do |value|
      it "rejects #{value.inspect} with a helpful message" do
        deposit.deposit_date = value
        expect(deposit).not_to be_valid
        expect(deposit.errors[:deposit_date]).to eq(['must be a valid date in YYYY-MM-DD format'])
      end
    end
  end

  describe 'idempotency_key' do
    it { is_expected.to validate_length_of(:idempotency_key).is_at_most(255) }
  end

  describe 'immutability' do
    let!(:deposit) { create(:deposit) }

    it 'cannot be updated once created' do
      expect { deposit.update!(amount: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'cannot be destroyed once created' do
      expect { deposit.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe 'database constraints' do
    it 'rejects a non-positive amount even when validations are skipped' do
      deposit = build(:deposit, tradeline: create(:tradeline), amount: 0)
      expect { deposit.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/)
    end

    it 'enforces unique idempotency keys per tradeline' do
      existing = create(:deposit, idempotency_key: 'abc')
      duplicate = build(:deposit, tradeline: existing.tradeline, idempotency_key: 'abc')
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same idempotency key on different tradelines' do
      create(:deposit, idempotency_key: 'abc')
      expect { create(:deposit, idempotency_key: 'abc') }.not_to raise_error
    end
  end
end
