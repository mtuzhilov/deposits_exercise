require 'rails_helper'

RSpec.describe 'Deposits API', type: :request do
  let(:headers) { json_headers(:operator) }
  let(:tradeline) { create(:tradeline, amount: '1000.00') }
  let(:path) { "/tradelines/#{tradeline.id}/deposits" }

  def create_deposit(body, extra_headers = {})
    post path, params: body.to_json, headers: headers.merge(extra_headers)
  end

  describe 'POST /tradelines/:tradeline_id/deposits' do
    it 'creates a deposit and returns the new balance' do
      create_deposit(deposit: { amount: '250.00', deposit_date: '2026-12-01' })

      expect(response).to have_http_status(:created)
      expect(json).to include('tradeline_id' => tradeline.id, 'amount' => '250.00', 'deposit_date' => '2026-12-01',
                              'tradeline_outstanding_balance' => '750.00')
      expect(response.headers['location']).to end_with("#{path}/#{json['id']}")
    end

    it 'accepts unwrapped attributes and JSON numbers' do
      create_deposit(amount: 99.99, deposit_date: '2026-12-01')
      expect(response).to have_http_status(:created)
      expect(json['amount']).to eq('99.99')
    end

    it 'updates the balance shown on the tradeline' do
      create_deposit(amount: '400.00', deposit_date: '2026-12-01')
      get "/tradelines/#{tradeline.id}", headers: headers
      expect(json['outstanding_balance']).to eq('600.00')
    end

    it 'allows depositing the exact outstanding balance' do
      create_deposit(amount: '1000.00', deposit_date: '2026-12-01')
      expect(response).to have_http_status(:created)
      expect(json['tradeline_outstanding_balance']).to eq('0.00')
    end

    it 'rejects a deposit that exceeds the outstanding balance' do
      create_deposit(amount: '600.00', deposit_date: '2026-12-01')
      create_deposit(amount: '400.01', deposit_date: '2026-12-02')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to eq('error' => {
                           'code' => 'insufficient_balance',
                           'message' => 'Deposit exceeds the outstanding balance',
                           'details' => { 'amount' => ['exceeds the outstanding balance of 400.00'] }
                         })
      expect(tradeline.reload.deposits.count).to eq(1)
    end

    it 'rejects any deposit on a fully paid tradeline' do
      create_deposit(amount: '1000.00', deposit_date: '2026-12-01')
      create_deposit(amount: '0.01', deposit_date: '2026-12-01')
      expect(json.dig('error', 'code')).to eq('insufficient_balance')
    end

    it 'returns all validation errors at once' do
      create_deposit(amount: '0', deposit_date: '2026-02-30')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.dig('error', 'code')).to eq('validation_failed')
      expect(json.dig('error', 'details')).to eq(
        'amount' => ['must be greater than 0'],
        'deposit_date' => ['must be a valid date in YYYY-MM-DD format']
      )
    end

    it 'reports missing fields' do
      create_deposit(deposit: { note: 'hi' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.dig('error', 'details').keys).to contain_exactly('amount', 'deposit_date')
    end

    it 'returns 400 for an empty body' do
      create_deposit({})
      expect(response).to have_http_status(:bad_request)
      expect(json.dig('error', 'message')).to eq('Missing required parameter: deposit')
    end

    it 'returns 400 for malformed JSON' do
      post path, params: '{"amount": 10,', headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(json.dig('error', 'message')).to eq('Request body is not valid JSON')
    end

    it 'returns 404 for an unknown tradeline' do
      post '/tradelines/0/deposits', params: { amount: 1, deposit_date: '2026-12-01' }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(json.dig('error', 'message')).to eq('Tradeline not found')
    end

    it 'ignores a client-supplied tradeline_id in the body' do
      other = create(:tradeline)
      create_deposit(amount: '1.00', deposit_date: '2026-12-01', tradeline_id: other.id)
      expect(json['tradeline_id']).to eq(tradeline.id)
    end

    describe 'Idempotency-Key' do
      let(:body) { { amount: '100.00', deposit_date: '2026-12-01' } }

      it 'returns the original deposit for a retried request' do
        create_deposit(body, 'Idempotency-Key' => 'abc-123')
        first_id = json['id']
        create_deposit(body, 'Idempotency-Key' => 'abc-123')

        expect(response).to have_http_status(:ok)
        expect(response.headers['idempotent-replayed']).to eq('true')
        expect(json['id']).to eq(first_id)
        expect(json['tradeline_outstanding_balance']).to eq('900.00')
        expect(tradeline.deposits.count).to eq(1)
      end

      it 'rejects reusing the key with a different payload' do
        create_deposit(body, 'Idempotency-Key' => 'abc-123')
        create_deposit(body.merge(amount: '5.00'), 'Idempotency-Key' => 'abc-123')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig('error', 'code')).to eq('idempotency_key_reused')
      end

      it 'creates separate deposits without a key' do
        2.times { create_deposit(body) }
        expect(tradeline.deposits.count).to eq(2)
      end

      it 'rejects an overly long key' do
        create_deposit(body, 'Idempotency-Key' => 'k' * 256)
        expect(json.dig('error', 'details', 'idempotency_key')).to include(/too long/)
      end
    end
  end

  describe 'GET /tradelines/:tradeline_id/deposits' do
    it 'lists the deposits of that tradeline in date order' do
      later = create(:deposit, tradeline: tradeline, amount: 10, deposit_date: '2027-01-01')
      earlier = create(:deposit, tradeline: tradeline, amount: 20, deposit_date: '2026-11-01')
      create(:deposit) # another tradeline

      get path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json.pluck('id')).to eq([earlier.id, later.id])
      expect(json.first).to eq(
        'id' => earlier.id, 'tradeline_id' => tradeline.id, 'amount' => '20.00',
        'deposit_date' => '2026-11-01', 'created_at' => earlier.created_at.as_json
      )
    end

    it 'returns an empty array for a tradeline without deposits' do
      get path, headers: headers
      expect(json).to eq([])
    end

    it 'is paginated' do
      3.times { create(:deposit, tradeline: tradeline, amount: 1) }
      get path, params: { limit: 2 }, headers: headers
      expect(json.size).to eq(2)
      expect(response.headers['total-count']).to eq('3')
    end

    it 'returns 404 for an unknown tradeline' do
      get '/tradelines/0/deposits', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /tradelines/:tradeline_id/deposits/:id' do
    let(:deposit) { create(:deposit, tradeline: tradeline, amount: '125.75', deposit_date: '2026-12-15') }

    it 'returns the deposit' do
      get "#{path}/#{deposit.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to include('id' => deposit.id, 'amount' => '125.75', 'deposit_date' => '2026-12-15',
                              'tradeline_outstanding_balance' => '874.25')
    end

    it 'returns 404 for a deposit that belongs to another tradeline' do
      other = create(:deposit)
      get "#{path}/#{other.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json.dig('error', 'message')).to eq('Deposit not found')
    end

    it 'returns 404 for an unknown deposit' do
      get "#{path}/0", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
