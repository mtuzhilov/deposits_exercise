require 'rails_helper'

RSpec.describe AuditEvent, type: :model do
  it { is_expected.to belong_to(:api_key).optional }
  it { is_expected.to belong_to(:auditable).optional }
  it { is_expected.to validate_inclusion_of(:action).in_array(described_class::ACTIONS) }

  describe '.record!' do
    let(:api_key) { create(:api_key, role: 'operator') }
    let(:tradeline) { create(:tradeline) }

    before do
      Current.api_key = api_key
      Current.request_id = 'req-123'
      Current.ip_address = '203.0.113.7'
      Current.user_agent = 'x' * 300
    end

    after { Current.reset }

    it 'captures the actor and request context' do
      event = described_class.record!('tradeline.created', auditable: tradeline, metadata: { amount: '10.00' })

      expect(event).to have_attributes(
        api_key: api_key, auditable: tradeline, request_id: 'req-123', ip_address: '203.0.113.7',
        metadata: { 'amount' => '10.00' }
      )
    end

    it 'truncates very long user agents' do
      expect(described_class.record!('tradeline.created').user_agent.length).to eq(255)
    end
  end

  describe 'append-only' do
    let!(:event) { create(:audit_event) }

    it 'cannot be updated' do
      expect { event.update!(action: 'tradeline.created') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'cannot be destroyed' do
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(described_class.exists?(event.id)).to be(true)
    end
  end
end
