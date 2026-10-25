require 'swagger_helper'

RSpec.describe 'Tradelines', type: :request do
  let(:Authorization) { bearer(:viewer) }

  path '/tradelines' do
    get 'List tradelines' do
      tags 'Tradelines'
      operationId 'listTradelines'
      description <<~MD
        Returns tradelines ordered by id, each with its current `outstanding_balance`.
        Paginated — see the pagination headers. **Role:** `viewer` or higher.
      MD
      produces 'application/json'
      parameter '$ref' => '#/components/parameters/page'
      parameter '$ref' => '#/components/parameters/limit'

      response '200', 'A page of tradelines' do
        paginated_headers
        schema type: :array, items: { '$ref' => '#/components/schemas/Tradeline' }

        before do
          card = create(:tradeline, name: 'Visa Gold', amount: '1000.00')
          create(:deposit, tradeline: card, amount: '350.00')
          create(:tradeline, name: 'Auto Loan', amount: '18500.00')
        end

        run_test! do
          expect(json.pluck('outstanding_balance')).to eq(%w[650.00 18500.00])
        end
      end

      response '400', 'Invalid pagination parameter' do
        schema '$ref' => '#/components/schemas/BadRequestError'
        let(:page) { 0 }
        run_test!
      end

      unauthorized_response
    end

    post 'Create a tradeline' do
      tags 'Tradelines'
      operationId 'createTradeline'
      description <<~MD
        Creates a tradeline. The body may be flat (`{"name": …}`) or wrapped (`{"tradeline": {"name": …}}`).
        Recorded in the audit log as `tradeline.created`. **Role:** `admin`.
      MD
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/TradelineInput' }
      request_body_example value: { name: 'Visa Gold', amount: '1000.00' }, name: 'credit_card', summary: 'Credit card'
      request_body_example value: { name: 'Auto Loan', amount: '18500.00' }, name: 'auto_loan', summary: 'Auto loan'

      let(:Authorization) { bearer(:admin) }
      let(:body) { { name: 'Visa Gold', amount: '1000.00' } }

      response '201', 'Tradeline created' do
        header 'location', schema: { type: :string }, description: 'URL of the new tradeline.'
        schema '$ref' => '#/components/schemas/Tradeline'
        run_test! do
          expect(json).to include('amount' => '1000.00', 'outstanding_balance' => '1000.00')
        end
      end

      response '400', 'Missing or malformed body' do
        schema '$ref' => '#/components/schemas/BadRequestError'
        let(:body) { {} }
        run_test!
      end

      response '422', 'Validation failed' do
        schema '$ref' => '#/components/schemas/ValidationError'
        example 'application/json', :validation_failed, {
          error: { code: 'validation_failed', message: 'Tradeline is invalid',
                   details: { name: ["can't be blank"], amount: ['must have at most 2 decimal places'] } }
        }, 'Blank name and fractional cents'
        let(:body) { { name: '', amount: '10.005' } }
        run_test!
      end

      unauthorized_response
      forbidden_response(:operator)
    end
  end

  path '/tradelines/{id}' do
    parameter name: :id, in: :path, required: true, schema: { type: :integer }, description: 'Tradeline id.'

    get 'Show a tradeline' do
      tags 'Tradelines'
      operationId 'getTradeline'
      description 'Returns one tradeline with its current `outstanding_balance`. **Role:** `viewer` or higher.'
      produces 'application/json'

      let(:tradeline) { create(:tradeline, name: 'Visa Gold', amount: '1000.00') }
      let(:id) { tradeline.id }

      response '200', 'The tradeline' do
        schema '$ref' => '#/components/schemas/Tradeline'
        before { create(:deposit, tradeline: tradeline, amount: '350.00') }
        run_test! do
          expect(json).to include('deposits_total' => '350.00', 'outstanding_balance' => '650.00')
        end
      end

      response '404', 'Tradeline not found' do
        schema '$ref' => '#/components/schemas/NotFoundError'
        let(:id) { 0 }
        run_test!
      end

      unauthorized_response
    end
  end
end
