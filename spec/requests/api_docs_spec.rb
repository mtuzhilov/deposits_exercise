require 'rails_helper'

RSpec.describe 'API documentation', type: :request do
  it 'redirects the root URL to the docs' do
    get '/'
    expect(response).to redirect_to('/api-docs')
  end

  it 'serves Swagger UI without authentication' do
    get '/api-docs/index.html'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('/api-docs/v1/openapi.json', '"persistAuthorization":true')
  end

  describe 'GET /api-docs/v1/openapi.json' do
    before { get '/api-docs/v1/openapi.json', headers: { 'Host' => 'deposits.example.com' } }

    let(:document) { JSON.parse(response.body) }

    it 'serves the OpenAPI document' do
      expect(response).to have_http_status(:ok)
      expect(document).to include('openapi' => '3.0.3')
      expect(document.dig('info', 'title')).to eq('Deposits API')
    end

    it 'targets the host serving the docs so "Try it out" works anywhere' do
      expect(document['servers']).to eq([{ 'url' => 'http://deposits.example.com', 'description' => 'This server' }])
    end

    it 'documents every API route' do
      documented = document['paths'].flat_map do |path, operations|
        (operations.keys & %w[get post put patch delete]).map do |verb|
          "#{verb.upcase} #{path.gsub(/\{(\w+)\}/, ':\1')}"
        end
      end

      routed = Rails.application.routes.routes.filter_map do |route|
        controller = route.defaults[:controller]
        next if controller.nil? || (controller.start_with?('rails/') && controller != 'rails/health')

        "#{route.verb} #{route.path.spec.to_s.sub('(.:format)', '')}"
      end

      expect(documented).to match_array(routed)
    end

    it 'requires bearer auth on everything except the health check' do
      expect(document['security']).to eq([{ 'bearer_auth' => [] }])
      expect(document.dig('paths', '/up', 'get', 'security')).to eq([])
    end
  end
end
