require 'rails_helper'

RSpec.describe 'Tradelines API', type: :request do
  let(:headers) { json_headers(:admin) }

  describe 'GET /tradelines' do
    it 'lists tradelines with their outstanding balance' do
      tradeline = create(:tradeline, name: 'Card', amount: '3223.54')
      create(:deposit, tradeline: tradeline, amount: '223.54')
      create(:tradeline, name: 'Loan', amount: '500.00')

      get '/tradelines', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to match([
        a_hash_including('id' => tradeline.id, 'name' => 'Card', 'amount' => '3223.54',
                         'deposits_total' => '223.54', 'outstanding_balance' => '3000.00'),
        a_hash_including('name' => 'Loan', 'amount' => '500.00', 'deposits_total' => '0.00',
                         'outstanding_balance' => '500.00')
      ])
    end

    it 'returns an empty array when there are no tradelines' do
      get '/tradelines', headers: headers
      expect(json).to eq([])
    end

    it 'serializes money as strings with exactly 2 decimals' do
      create(:tradeline, amount: 18_500)
      get '/tradelines', headers: headers
      expect(json.first.values_at('amount', 'outstanding_balance')).to eq(%w[18500.00 18500.00])
    end

    it 'returns null balance for a legacy tradeline without an amount' do
      build(:tradeline, amount: nil).save!(validate: false)
      get '/tradelines', headers: headers
      expect(json.first).to include('amount' => nil, 'outstanding_balance' => nil)
    end

    it 'does not run a query per tradeline' do
      create_list(:tradeline, 5)
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /FROM "tradelines"/ }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get '/tradelines', headers: headers }
      expect(queries.size).to be <= 2 # page + count
    end

    describe 'pagination' do
      before { create_list(:tradeline, 30) }

      it 'defaults to 25 per page and exposes pagination headers' do
        get '/tradelines', headers: headers

        expect(json.size).to eq(25)
        expect(response.headers).to include('total-count' => '30', 'total-pages' => '2', 'current-page' => '1',
                                            'page-items' => '25')
        expect(response.headers['link']).to include('rel="next"')
      end

      it 'supports page and limit' do
        get '/tradelines', params: { page: 2, limit: 10 }, headers: headers
        expect(json.size).to eq(10)
        expect(json.first['id']).to eq(Tradeline.order(:id).offset(10).first.id)
      end

      it 'caps limit at 100' do
        get '/tradelines', params: { limit: 1000 }, headers: headers
        expect(response.headers['page-items']).to eq('100')
      end

      it 'returns an empty page past the end' do
        get '/tradelines', params: { page: 99 }, headers: headers
        expect(response).to have_http_status(:ok)
        expect(json).to eq([])
      end

      it 'rejects an invalid page' do
        get '/tradelines', params: { page: 0 }, headers: headers
        expect(response).to have_http_status(:bad_request)
        expect(json.dig('error', 'code')).to eq('bad_request')
      end
    end
  end

  describe 'GET /tradelines/:id' do
    it 'returns the tradeline with its outstanding balance' do
      tradeline = create(:tradeline, amount: '1000.00')
      create(:deposit, tradeline: tradeline, amount: '250.50')

      get "/tradelines/#{tradeline.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to include('id' => tradeline.id, 'amount' => '1000.00', 'deposits_total' => '250.50',
                              'outstanding_balance' => '749.50')
    end

    it 'returns a structured 404 for an unknown tradeline' do
      get '/tradelines/0', headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json).to eq('error' => { 'code' => 'not_found', 'message' => 'Tradeline not found' })
    end

    it 'responds with JSON even when the client asks for HTML' do
      tradeline = create(:tradeline)
      get "/tradelines/#{tradeline.id}", headers: auth_headers.merge('Accept' => 'text/html')
      expect(response.media_type).to eq('application/json')
    end
  end

  describe 'POST /tradelines' do
    it 'creates a tradeline' do
      post '/tradelines', params: { tradeline: { name: 'Mortgage', amount: '250000.00' } }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(response.headers['location']).to end_with("/tradelines/#{json['id']}")
      expect(json).to include('name' => 'Mortgage', 'amount' => '250000.00', 'outstanding_balance' => '250000.00')
    end

    it 'accepts unwrapped attributes' do
      post '/tradelines', params: { name: 'Mortgage', amount: 100 }.to_json, headers: headers
      expect(response).to have_http_status(:created)
    end

    it 'audits the creation' do
      post '/tradelines', params: { name: 'Mortgage', amount: '10.00' }.to_json, headers: headers
      event = AuditEvent.find_by!(action: 'tradeline.created')
      expect(event).to have_attributes(auditable_id: json['id'], metadata: { 'name' => 'Mortgage', 'amount' => '10.00' })
    end

    it 'returns validation errors' do
      post '/tradelines', params: { tradeline: { name: '', amount: '-1.005' } }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to include('code' => 'validation_failed', 'message' => 'Tradeline is invalid')
      expect(json.dig('error', 'details', 'name')).to include("can't be blank")
      expect(json.dig('error', 'details', 'amount')).to include('must have at most 2 decimal places')
      expect(AuditEvent.count).to eq(0)
    end

    it 'returns 400 when no attributes are sent' do
      post '/tradelines', params: {}.to_json, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(json.dig('error', 'message')).to eq('Missing required parameter: tradeline')
    end

    it 'ignores attributes that clients must not set' do
      post '/tradelines', params: { name: 'X', amount: 100, deposits_total: 100 }.to_json, headers: headers
      expect(json['deposits_total']).to eq('0.00')
    end
  end
end
