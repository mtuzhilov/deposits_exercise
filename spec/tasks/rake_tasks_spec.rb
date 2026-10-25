require 'rails_helper'
require 'rake'

RSpec.describe 'rake tasks' do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  def task_output(name, *args)
    task = Rake::Task[name]
    task.reenable
    capture = StringIO.new
    original = $stdout
    $stdout = capture
    task.invoke(*args)
    capture.string
  ensure
    $stdout = original
  end

  describe 'auth:create_key' do
    it 'issues a key and prints the token once' do
      output = task_output('auth:create_key', 'reporting', 'viewer')

      token = output.lines.last.strip
      expect(output).to include("Created viewer key 'reporting'")
      expect(ApiKey.authenticate(token)).to have_attributes(name: 'reporting', role: 'viewer')
    end

    it 'supports an expiry' do
      ENV['EXPIRES_IN_DAYS'] = '7'
      task_output('auth:create_key', 'temp', 'admin')
      expect(ApiKey.last.expires_at).to be_within(1.minute).of(7.days.from_now)
    ensure
      ENV.delete('EXPIRES_IN_DAYS')
    end

    it 'refuses an invalid role' do
      expect { task_output('auth:create_key', 'x', 'root') }.to raise_error(SystemExit)
      expect(ApiKey.count).to eq(0)
    end
  end

  describe 'auth:list_keys' do
    it 'lists keys without revealing tokens' do
      key, token = ApiKey.issue!(name: 'ledger', role: :operator)
      output = task_output('auth:list_keys')

      expect(output).to include(key.token_prefix, 'operator', 'active', 'ledger')
      expect(output).not_to include(token)
    end
  end

  describe 'auth:revoke_key' do
    it 'revokes the key with that prefix' do
      key, token = ApiKey.issue!(name: 'old', role: :admin)
      task_output('auth:revoke_key', key.token_prefix)

      expect(key.reload.status).to eq('revoked')
      expect(ApiKey.authenticate(token)).to be_nil
    end

    it 'fails for an unknown prefix' do
      expect { task_output('auth:revoke_key', 'dpx_nope') }.to raise_error(SystemExit)
    end
  end

  describe 'deposits:reconcile' do
    let(:tradeline) { create(:tradeline, amount: 100) }

    before { create(:deposit, tradeline: tradeline, amount: 30) }

    it 'passes when every total matches' do
      expect(task_output('deposits:reconcile')).to include('All tradelines reconcile.')
    end

    it 'reports drift and exits non-zero' do
      Tradeline.where(id: tradeline.id).update_all(deposits_total: 20)
      expect { task_output('deposits:reconcile') }.to raise_error(SystemExit)
    end

    it 'repairs drift with FIX=1' do
      Tradeline.where(id: tradeline.id).update_all(deposits_total: 20)
      ENV['FIX'] = '1'
      expect(task_output('deposits:reconcile')).to include('(repaired)')
      expect(tradeline.reload.deposits_total).to eq(30)
    ensure
      ENV.delete('FIX')
    end
  end
end
