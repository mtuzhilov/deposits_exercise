require 'rails_helper'

RSpec.describe Deposits::Create do
  let(:tradeline) { create(:tradeline, amount: '1000.00') }
  let(:params) { { amount: '250.00', deposit_date: '2026-12-01' } }
  let(:idempotency_key) { nil }

  subject(:result) { described_class.call(tradeline: tradeline, params: params, idempotency_key: idempotency_key) }

  context 'with a valid deposit' do
    it 'creates the deposit' do
      expect { result }.to change(Deposit, :count).by(1)
      expect(result).to be_success
      expect(result.status).to eq(:created)
      expect(result.deposit).to have_attributes(amount: BigDecimal('250'), deposit_date: Date.new(2026, 12, 1))
    end

    it 'reduces the outstanding balance' do
      result
      expect(tradeline.reload.outstanding_balance).to eq(BigDecimal('750'))
    end

    it 'records an audit event with balances before and after' do
      expect { result }.to change { AuditEvent.where(action: 'deposit.created').count }.by(1)
      expect(AuditEvent.last).to have_attributes(auditable: result.deposit)
      expect(AuditEvent.last.metadata).to include(
        'amount' => '250.00', 'outstanding_balance_before' => '1000.00', 'outstanding_balance_after' => '750.00'
      )
    end
  end

  context 'when the deposit equals the outstanding balance exactly' do
    let(:params) { { amount: '1000.00', deposit_date: '2026-12-01' } }

    it 'is accepted and leaves a zero balance' do
      expect(result).to be_success
      expect(tradeline.reload.outstanding_balance).to eq(0)
    end
  end

  context 'with amounts that are inexact in floating point' do
    let(:tradeline) { create(:tradeline, amount: '3223.54') }

    it 'still allows depositing exactly the remaining balance' do
      described_class.call(tradeline: tradeline, params: { amount: '3000.00', deposit_date: '2026-12-01' })
      remaining = described_class.call(tradeline: tradeline, params: { amount: '223.54', deposit_date: '2026-12-02' })

      expect(remaining).to be_success
      expect(tradeline.reload.outstanding_balance).to eq(0)
    end

    it 'accumulates many cent-level deposits without drift' do
      tradeline = create(:tradeline, amount: '0.30')
      3.times { described_class.call(tradeline: tradeline, params: { amount: '0.10', deposit_date: '2026-12-01' }) }

      expect(tradeline.reload.deposits.count).to eq(3)
      expect(tradeline.outstanding_balance).to eq(0)
      expect(tradeline.deposits_total_drift).to eq(0)
    end
  end

  context 'when the deposit exceeds the outstanding balance' do
    let(:params) { { amount: '1000.01', deposit_date: '2026-12-01' } }

    it 'is rejected without side effects' do
      expect { result }.not_to change(Deposit, :count)
      expect(tradeline.reload.deposits_total).to eq(0)
    end

    it 'explains why' do
      expect(result).not_to be_success
      expect(result.status).to eq(:unprocessable_entity)
      expect(result.error_code).to eq('insufficient_balance')
      expect(result.errors).to eq(amount: ['exceeds the outstanding balance of 1000.00'])
    end

    it 'records the rejected attempt for review' do
      result
      event = AuditEvent.find_by!(action: 'deposit.rejected')
      expect(event.auditable).to eq(tradeline)
      expect(event.metadata).to include('reason' => 'insufficient_balance', 'requested_amount' => '1000.01',
                                        'outstanding_balance' => '1000.00')
    end
  end

  context 'when earlier deposits used up part of the balance' do
    before { create(:deposit, tradeline: tradeline, amount: '900.00') }

    it 'checks against what is left, not the original amount' do
      over = described_class.call(tradeline: tradeline, params: { amount: '100.01', deposit_date: '2026-12-01' })
      exact = described_class.call(tradeline: tradeline, params: { amount: '100.00', deposit_date: '2026-12-01' })

      expect(over.error_code).to eq('insufficient_balance')
      expect(exact).to be_success
    end
  end

  context 'with invalid input' do
    let(:params) { { amount: '-5', deposit_date: 'soon' } }

    it 'returns every validation error' do
      expect(result.error_code).to eq('validation_failed')
      expect(result.errors.keys).to contain_exactly(:amount, :deposit_date)
    end

    it 'does not touch the balance' do
      expect { result }.not_to(change { tradeline.reload.deposits_total })
    end
  end

  context 'when the tradeline has no amount' do
    let(:tradeline) { build(:tradeline, amount: nil).tap { |t| t.save!(validate: false) } }

    it 'refuses the deposit' do
      expect(result.error_code).to eq('tradeline_amount_missing')
      expect(Deposit.count).to eq(0)
    end
  end

  describe 'idempotency' do
    let(:idempotency_key) { 'order-42' }

    it 'returns the original deposit when the same request is retried' do
      first = described_class.call(tradeline: tradeline, params: params, idempotency_key: idempotency_key)

      expect { result }.not_to change(Deposit, :count)
      expect(result).to be_success
      expect(result.status).to eq(:ok)
      expect(result.replayed).to be(true)
      expect(result.deposit).to eq(first.deposit)
      expect(tradeline.reload.outstanding_balance).to eq(BigDecimal('750'))
    end

    it 'treats equivalent amounts as the same request' do
      described_class.call(tradeline: tradeline, params: params, idempotency_key: idempotency_key)
      retry_result = described_class.call(tradeline: tradeline, params: params.merge(amount: 250),
                                          idempotency_key: idempotency_key)
      expect(retry_result).to be_success
    end

    it 'rejects reusing a key for a different deposit' do
      described_class.call(tradeline: tradeline, params: params, idempotency_key: idempotency_key)
      other = described_class.call(tradeline: tradeline, params: params.merge(amount: '1.00'),
                                   idempotency_key: idempotency_key)

      expect(other.error_code).to eq('idempotency_key_reused')
      expect(Deposit.count).to eq(1)
    end

    it 'scopes keys to the tradeline' do
      described_class.call(tradeline: tradeline, params: params, idempotency_key: idempotency_key)
      other = described_class.call(tradeline: create(:tradeline), params: params, idempotency_key: idempotency_key)

      expect(other.status).to eq(:created)
    end

    it 'audits the replay' do
      described_class.call(tradeline: tradeline, params: params, idempotency_key: idempotency_key)
      expect { result }.to change { AuditEvent.where(action: 'deposit.idempotent_replay').count }.by(1)
    end
  end

  # Runs real threads, each with its own database connection, so this cannot
  # use a wrapping test transaction.
  describe 'concurrent deposits', :concurrency do
    self.use_transactional_tests = false

    after do
      AuditEvent.delete_all
      Deposit.delete_all
      Tradeline.delete_all
    end

    def deposit_concurrently(tradeline, count:, amount:, key: nil)
      start = Concurrent::CountDownLatch.new(1)
      threads = Array.new(count) do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.wait
            described_class.call(tradeline: Tradeline.find(tradeline.id),
                                 params: { amount: amount, deposit_date: '2026-12-01' },
                                 idempotency_key: key || "k-#{i}")
          end
        end
      end
      start.count_down
      threads.map(&:value)
    end

    it 'never lets the deposits exceed the tradeline amount' do
      tradeline = create(:tradeline, amount: '500.00')
      results = deposit_concurrently(tradeline, count: 5, amount: '150.00')

      expect(results.count(&:success?)).to eq(3)
      expect(results.reject(&:success?).map(&:error_code)).to all(eq('insufficient_balance'))
      expect(tradeline.reload.deposits_total).to eq(BigDecimal('450'))
      expect(tradeline.deposits.count).to eq(3)
    end

    it 'creates exactly one deposit for concurrent retries with the same idempotency key' do
      tradeline = create(:tradeline, amount: '500.00')
      results = deposit_concurrently(tradeline, count: 5, amount: '100.00', key: 'same-key')

      expect(results).to all(be_success)
      expect(results.map { |r| r.deposit.id }.uniq.size).to eq(1)
      expect(tradeline.reload.deposits_total).to eq(BigDecimal('100'))
    end
  end
end
