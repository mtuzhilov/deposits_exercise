require 'rails_helper'

RSpec.describe 'Audit events API', type: :request do
  let(:admin_headers) { json_headers(:admin) }
  let(:operator_issued) { ApiKey.issue!(name: 'payments-service', role: :operator) }
  let(:operator_headers) do
    { 'Authorization' => "Bearer #{operator_issued.last}", 'Content-Type' => 'application/json',
      'User-Agent' => 'payments/1.0' }
  end
  let(:tradeline) { create(:tradeline, amount: '100.00') }

  def deposit!(amount)
    post "/tradelines/#{tradeline.id}/deposits", params: { amount: amount, deposit_date: '2026-12-01' }.to_json,
                                                 headers: operator_headers
    response
  end

  it 'records who made a deposit, from where and in which request' do
    request_id = deposit!('40.00').headers['x-request-id']

    get '/audit_events', headers: admin_headers

    expect(response).to have_http_status(:ok)
    event = json.find { |e| e['action'] == 'deposit.created' }
    expect(event).to include(
      'auditable_type' => 'Deposit', 'request_id' => request_id, 'ip_address' => '127.0.0.1',
      'user_agent' => 'payments/1.0',
      'actor' => { 'id' => operator_issued.first.id, 'name' => 'payments-service', 'role' => 'operator',
                   'token_prefix' => operator_issued.first.token_prefix }
    )
    expect(event['metadata']).to include('amount' => '40.00', 'outstanding_balance_before' => '100.00',
                                         'outstanding_balance_after' => '60.00')
  end

  it 'records rejected deposits' do
    deposit!('100.01')

    get '/audit_events', params: { event: 'deposit.rejected' }, headers: admin_headers

    expect(json.size).to eq(1)
    expect(json.first).to include('auditable_type' => 'Tradeline', 'auditable_id' => tradeline.id)
    expect(json.first['metadata']).to include('reason' => 'insufficient_balance', 'requested_amount' => '100.01')
  end

  it 'lists newest first and filters by auditable' do
    deposit!('10.00')
    deposit!('20.00')
    second = Deposit.order(:id).last

    get '/audit_events', params: { auditable_type: 'Deposit', auditable_id: second.id }, headers: admin_headers

    expect(json.size).to eq(1)
    expect(json.first['metadata']['amount']).to eq('20.00')
  end

  it 'filters by actor' do
    deposit!('10.00')
    create(:audit_event, action: 'tradeline.created')

    get '/audit_events', params: { api_key_id: operator_issued.first.id }, headers: admin_headers

    expect(json.pluck('action')).to eq(['deposit.created'])
  end

  it 'is paginated' do
    3.times { create(:audit_event) }
    get '/audit_events', params: { limit: 2 }, headers: admin_headers
    expect(json.size).to eq(2)
    expect(response.headers['total-count']).to eq('3')
  end

  it 'never exposes credentials' do
    deposit!('10.00')
    get '/audit_events', headers: admin_headers
    expect(response.body).not_to include(operator_issued.last)
    expect(response.body).not_to include(operator_issued.first.token_digest)
  end
end
