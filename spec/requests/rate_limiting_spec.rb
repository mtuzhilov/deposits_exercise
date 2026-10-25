require 'rails_helper'

RSpec.describe 'Rate limiting', type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    example.run
  ensure
    Rack::Attack.reset!
    Rack::Attack.enabled = false
  end

  it 'throttles unauthenticated requests per IP' do
    20.times { get '/tradelines' }
    expect(response).to have_http_status(:unauthorized)

    get '/tradelines'

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['retry-after'].to_i).to be_between(1, 60)
    expect(json.dig('error', 'code')).to eq('rate_limited')
  end

  it 'gives authenticated clients their own, larger budget' do
    20.times { get '/tradelines' }
    get '/tradelines', headers: auth_headers(:viewer)
    expect(response).to have_http_status(:ok)
  end

  it 'never throttles the health check' do
    25.times { get '/up' }
    expect(response).to have_http_status(:ok)
  end
end
