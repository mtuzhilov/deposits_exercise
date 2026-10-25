require 'swagger_helper'

RSpec.describe 'Health', type: :request do
  path '/up' do
    get 'Health check' do
      tags 'Health'
      operationId 'healthCheck'
      description 'Returns 200 when the application boots and can serve requests. No authentication.'
      security []
      produces 'text/html'

      response '200', 'The application is up' do
        run_test!
      end
    end
  end
end
