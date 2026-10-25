require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  describe '.issue!' do
    let(:issued) { described_class.issue!(name: 'billing-service', role: :operator) }
    let(:key) { issued.first }
    let(:token) { issued.last }

    it 'returns a prefixed, high-entropy token' do
      expect(token).to match(/\Adpx_[A-Za-z0-9_-]{43}\z/)
    end

    it 'stores only a digest of the token' do
      expect(key.token_digest).to eq(Digest::SHA256.hexdigest(token))
      stored_values = described_class.connection.select_rows('SELECT * FROM api_keys').flatten.map(&:to_s)
      expect(stored_values).not_to include(token)
    end

    it 'keeps a short display prefix for identification' do
      expect(key.token_prefix).to eq(token.first(12))
    end

    it 'issues unique tokens' do
      tokens = Array.new(5) { described_class.issue!(name: 'x', role: :viewer).last }
      expect(tokens.uniq.size).to eq(5)
    end

    it 'rejects unknown roles' do
      expect { described_class.issue!(name: 'x', role: :superuser) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'validations' do
    subject { build(:api_key) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:role).in_array(described_class::ROLES) }
    it { is_expected.to validate_uniqueness_of(:token_digest) }

    it 'enforces the role list in the database too' do
      expect { build(:api_key, role: 'root').save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/)
    end
  end

  describe '.authenticate' do
    let!(:issued) { described_class.issue!(name: 'client', role: :viewer) }
    let(:key) { issued.first }
    let(:token) { issued.last }

    it 'finds the key for a valid token' do
      expect(described_class.authenticate(token)).to eq(key)
    end

    it 'rejects an unknown token' do
      expect(described_class.authenticate("#{token}x")).to be_nil
    end

    it 'rejects blank and non-prefixed tokens without querying' do
      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate('')).to be_nil
      expect(described_class.authenticate(token.delete_prefix('dpx_'))).to be_nil
    end

    it 'rejects the stored digest used as a token' do
      expect(described_class.authenticate(key.token_digest)).to be_nil
    end

    it 'rejects a revoked key' do
      key.revoke!
      expect(described_class.authenticate(token)).to be_nil
    end

    it 'rejects an expired key' do
      key.update!(expires_at: 1.second.ago)
      expect(described_class.authenticate(token)).to be_nil
    end

    it 'accepts a key that expires in the future' do
      key.update!(expires_at: 1.hour.from_now)
      expect(described_class.authenticate(token)).to eq(key)
    end
  end

  describe '#can?' do
    {
      'viewer' => %i[read_tradelines read_deposits],
      'operator' => %i[read_tradelines read_deposits create_deposit],
      'admin' => %i[read_tradelines read_deposits create_deposit create_tradeline read_audit_events]
    }.each do |role, allowed|
      context "as #{role}" do
        let(:key) { build(:api_key, role: role) }

        it "grants #{allowed.join(', ')}" do
          allowed.each { |permission| expect(key.can?(permission)).to be(true) }
        end

        it 'denies everything else' do
          (described_class::PERMISSIONS['admin'] - allowed).each do |permission|
            expect(key.can?(permission)).to be(false)
          end
        end
      end
    end

    it 'denies unknown permissions' do
      expect(build(:api_key, role: 'admin').can?(:delete_everything)).to be(false)
    end
  end

  describe '#touch_last_used!' do
    let(:key) { create(:api_key) }

    it 'records first use' do
      expect { key.touch_last_used! }.to change { key.reload.last_used_at }.from(nil)
    end

    it 'writes at most once per minute' do
      key.update_column(:last_used_at, 30.seconds.ago)
      expect { key.touch_last_used! }.not_to(change { key.reload.last_used_at })
    end

    it 'updates again after the throttle window' do
      key.update_column(:last_used_at, 2.minutes.ago)
      expect { key.touch_last_used! }.to(change { key.reload.last_used_at })
    end
  end

  describe '#status' do
    it { expect(build(:api_key).status).to eq('active') }
    it { expect(build(:api_key, revoked_at: Time.current).status).to eq('revoked') }
    it { expect(build(:api_key, expires_at: 1.day.ago).status).to eq('expired') }
    it { expect(build(:api_key, expires_at: 1.day.from_now)).to be_active }
  end

  describe '#revoke!' do
    it 'does not move the revocation time when called twice' do
      key = create(:api_key)
      key.revoke!
      expect { key.revoke! }.not_to(change { key.reload.revoked_at })
    end
  end
end
