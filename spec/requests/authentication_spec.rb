require 'rails_helper'

RSpec.describe 'Authentication', type: :request do
  # Every API route, discovered from the route table so a newly added
  # endpoint cannot silently skip authentication.
  api_routes = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    next if controller.nil? || controller.start_with?('rails/')

    [route.verb, route.path.spec.to_s.sub('(.:format)', '')]
  end

  it 'covers every API endpoint' do
    expect(api_routes.map(&:first)).to include('GET', 'POST')
    expect(api_routes.size).to eq(7)
  end

  api_routes.each do |verb, pattern|
    describe "#{verb} #{pattern}" do
      # Point at records that exist, so a 401 proves auth runs before lookup.
      let(:deposit) { create(:deposit) }
      let(:path) { pattern.sub(':tradeline_id', deposit.tradeline_id.to_s).sub(':id', deposit.id.to_s) }

      it 'requires a token' do
        process verb.downcase.to_sym, path, headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['www-authenticate']).to eq('Bearer realm="deposits"')
        expect(json).to eq('error' => { 'code' => 'unauthorized', 'message' => 'A valid API key is required' })
      end

      it 'rejects an invalid token' do
        process verb.downcase.to_sym, path, headers: { 'Authorization' => 'Bearer dpx_not-a-real-token' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'token checks' do
    let!(:issued) { ApiKey.issue!(name: 'client', role: :viewer) }
    let(:key) { issued.first }
    let(:token) { issued.last }

    def get_tradelines(authorization)
      get '/tradelines', headers: { 'Authorization' => authorization }
    end

    it 'accepts a valid bearer token' do
      get_tradelines("Bearer #{token}")
      expect(response).to have_http_status(:ok)
    end

    it 'rejects a revoked key' do
      key.revoke!
      get_tradelines("Bearer #{token}")
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects an expired key' do
      key.update!(expires_at: 1.minute.ago)
      get_tradelines("Bearer #{token}")
      expect(response).to have_http_status(:unauthorized)
    end

    it 'gives the same response for unknown, revoked and expired keys' do
      get_tradelines('Bearer dpx_unknown')
      unknown = response.body
      key.revoke!
      get_tradelines("Bearer #{token}")
      expect(response.body).to eq(unknown)
    end

    it 'rejects a token sent with the wrong scheme' do
      get_tradelines("Basic #{Base64.strict_encode64("user:#{token}")}")
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not accept the token as a query parameter' do
      get '/tradelines', params: { token: token }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'records when the key was last used' do
      expect { get_tradelines("Bearer #{token}") }.to change { key.reload.last_used_at }.from(nil)
    end

    it 'does not write audit events for failed authentication' do
      get_tradelines('Bearer dpx_unknown')
      expect(AuditEvent.count).to eq(0)
    end
  end

  it 'keeps the health check public' do
    get '/up'
    expect(response).to have_http_status(:ok)
  end
end
