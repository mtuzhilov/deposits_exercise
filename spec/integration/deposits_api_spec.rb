# End-to-end tests over real HTTP against a running server. They do not load
# Rails or touch the database directly, so they verify the deployed behaviour.
#
#   bin/integration                         # boots a server, runs, shuts down
#   BASE_URL=http://localhost:3000 \
#   ADMIN_TOKEN=... OPERATOR_TOKEN=... VIEWER_TOKEN=... INTEGRATION=1 \
#     bundle exec rspec spec/integration    # against an already running server
require 'json'
require 'net/http'
require 'securerandom'

RSpec.describe 'Deposits API (live)', :integration do
  LiveResponse = Struct.new(:status, :headers, :body)

  let(:base_url) { ENV.fetch('BASE_URL', 'http://localhost:3000') }
  let(:tokens) do
    %w[ADMIN OPERATOR VIEWER].to_h do |role|
      [role.downcase.to_sym, ENV.fetch("#{role}_TOKEN") { raise "#{role}_TOKEN is not set (see bin/integration)" }]
    end
  end

  def request(method, path, body: nil, as: :admin, headers: {})
    uri = URI.join(base_url, path)
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method)
    req = klass.new(uri)
    req['Accept'] = 'application/json'
    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{tokens.fetch(as)}" if as
    headers.each { |k, v| req[k] = v }
    req.body = body.is_a?(String) ? body : body.to_json if body

    res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
    parsed = res.content_type == 'application/json' ? JSON.parse(res.body) : res.body
    LiveResponse.new(res.code.to_i, res.to_hash.transform_values(&:first), parsed)
  end

  def create_tradeline(amount)
    res = request(:post, '/tradelines', body: { name: "Integration #{SecureRandom.hex(4)}", amount: amount })
    expect(res.status).to eq(201), res.body.inspect
    res.body
  end

  def deposit(tradeline, amount, date = '2026-12-01', **opts)
    request(:post, "/tradelines/#{tradeline['id']}/deposits", body: { amount: amount, deposit_date: date }, **opts)
  end

  it 'serves an unauthenticated health check' do
    expect(request(:get, '/up', as: nil).status).to eq(200)
  end

  describe 'the assignment requirements' do
    it 'creates deposits and exposes the outstanding balance on show and index' do
      tradeline = create_tradeline('3223.54')
      expect(tradeline['outstanding_balance']).to eq('3223.54')

      first = deposit(tradeline, '1000.00', '2026-11-15')
      expect(first.status).to eq(201)
      expect(first.body).to include('amount' => '1000.00', 'deposit_date' => '2026-11-15',
                                    'tradeline_outstanding_balance' => '2223.54')

      expect(deposit(tradeline, '223.54', '2026-12-15').status).to eq(201)

      show = request(:get, "/tradelines/#{tradeline['id']}")
      expect(show.body).to include('amount' => '3223.54', 'deposits_total' => '1223.54',
                                   'outstanding_balance' => '2000.00')

      index_entry = nil
      page = 1
      until index_entry
        index = request(:get, "/tradelines?page=#{page}&limit=100")
        break if index.body.empty?

        index_entry = index.body.find { |t| t['id'] == tradeline['id'] }
        page += 1
      end
      expect(index_entry).to include('outstanding_balance' => '2000.00')
    end

    it 'rejects a deposit that exceeds the outstanding balance' do
      tradeline = create_tradeline('500.00')
      deposit(tradeline, '499.99')

      res = deposit(tradeline, '0.02')
      expect(res.status).to eq(422)
      expect(res.body['error']).to include('code' => 'insufficient_balance')
      expect(res.body.dig('error', 'details', 'amount')).to eq(['exceeds the outstanding balance of 0.01'])

      expect(deposit(tradeline, '0.01').status).to eq(201)
      expect(request(:get, "/tradelines/#{tradeline['id']}").body['outstanding_balance']).to eq('0.00')
    end

    it 'returns validation errors' do
      tradeline = create_tradeline('100.00')

      res = deposit(tradeline, '-1.005', 'next tuesday')
      expect(res.status).to eq(422)
      expect(res.body.dig('error', 'code')).to eq('validation_failed')
      expect(res.body.dig('error', 'details').keys).to contain_exactly('amount', 'deposit_date')

      malformed = request(:post, "/tradelines/#{tradeline['id']}/deposits", body: '{"amount":')
      expect(malformed.status).to eq(400)
    end

    it 'lists all deposits for a tradeline and shows an individual deposit' do
      tradeline = create_tradeline('1000.00')
      later = deposit(tradeline, '20.00', '2027-02-01').body
      earlier = deposit(tradeline, '10.00', '2027-01-01').body

      list = request(:get, "/tradelines/#{tradeline['id']}/deposits")
      expect(list.status).to eq(200)
      expect(list.body.map { |d| d['id'] }).to eq([earlier['id'], later['id']])
      expect(list.headers['total-count']).to eq('2')

      show = request(:get, "/tradelines/#{tradeline['id']}/deposits/#{later['id']}")
      expect(show.status).to eq(200)
      expect(show.body).to include('id' => later['id'], 'amount' => '20.00', 'deposit_date' => '2027-02-01')
    end

    it 'scopes deposits to their tradeline' do
      a = create_tradeline('100.00')
      b = create_tradeline('100.00')
      deposit_on_a = deposit(a, '5.00').body

      res = request(:get, "/tradelines/#{b['id']}/deposits/#{deposit_on_a['id']}")
      expect(res.status).to eq(404)
      expect(request(:get, '/tradelines/999999999/deposits').status).to eq(404)
    end
  end

  describe 'production safeguards' do
    it 'treats a retried request with the same Idempotency-Key as one deposit' do
      tradeline = create_tradeline('300.00')
      key = SecureRandom.uuid

      first = deposit(tradeline, '100.00', headers: { 'Idempotency-Key' => key })
      retry_res = deposit(tradeline, '100.00', headers: { 'Idempotency-Key' => key })

      expect([first.status, retry_res.status]).to eq([201, 200])
      expect(retry_res.headers['idempotent-replayed']).to eq('true')
      expect(retry_res.body['id']).to eq(first.body['id'])
      expect(request(:get, "/tradelines/#{tradeline['id']}").body['outstanding_balance']).to eq('200.00')
    end

    it 'never overdraws under concurrent requests' do
      tradeline = create_tradeline('1000.00')

      statuses = Array.new(10) { Thread.new { deposit(tradeline, '150.00').status } }.map(&:value)

      expect(statuses.count(201)).to eq(6)
      expect(statuses.count(422)).to eq(4)
      show = request(:get, "/tradelines/#{tradeline['id']}").body
      expect(show).to include('deposits_total' => '900.00', 'outstanding_balance' => '100.00')
    end
  end

  describe 'authentication and roles' do
    let(:tradeline) { create_tradeline('100.00') }

    it 'rejects requests without a valid token' do
      expect(request(:get, '/tradelines', as: nil).status).to eq(401)
      res = request(:get, '/tradelines', as: nil, headers: { 'Authorization' => 'Bearer dpx_wrong' })
      expect(res.status).to eq(401)
      expect(res.headers['www-authenticate']).to include('Bearer')
    end

    it 'lets viewers read but not write' do
      expect(request(:get, "/tradelines/#{tradeline['id']}", as: :viewer).status).to eq(200)
      expect(request(:get, "/tradelines/#{tradeline['id']}/deposits", as: :viewer).status).to eq(200)
      expect(deposit(tradeline, '1.00', as: :viewer).status).to eq(403)
    end

    it 'lets operators deposit but not create tradelines or read the audit log' do
      expect(deposit(tradeline, '1.00', as: :operator).status).to eq(201)
      expect(request(:post, '/tradelines', body: { name: 'x', amount: 1 }, as: :operator).status).to eq(403)
      expect(request(:get, '/audit_events', as: :operator).status).to eq(403)
    end

    it 'gives admins an audit trail of what happened' do
      created = deposit(tradeline, '25.00', as: :operator)
      deposit(tradeline, '1000.00', as: :operator)
      deposit(tradeline, '1.00', as: :viewer)

      events = request(:get, "/audit_events?auditable_type=Deposit&auditable_id=#{created.body['id']}").body
      expect(events.first).to include('action' => 'deposit.created', 'request_id' => created.headers['x-request-id'])
      expect(events.first.dig('actor', 'role')).to eq('operator')

      rejected = request(:get, "/audit_events?event=deposit.rejected&auditable_type=Tradeline&auditable_id=#{tradeline['id']}").body
      expect(rejected.first.dig('metadata', 'reason')).to eq('insufficient_balance')

      denied = request(:get, '/audit_events?event=authorization.denied&limit=5').body
      expect(denied.map { |e| e.dig('metadata', 'path') }).to include("/tradelines/#{tradeline['id']}/deposits")
    end
  end
end
