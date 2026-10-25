require 'swagger_helper'

RSpec.describe 'Deposits', type: :request do
  let(:Authorization) { bearer(:viewer) }
  let(:tradeline) { create(:tradeline, name: 'Visa Gold', amount: '1000.00') }
  let(:tradeline_id) { tradeline.id }

  path '/tradelines/{tradeline_id}/deposits' do
    parameter name: :tradeline_id, in: :path, required: true, schema: { type: :integer }, description: 'Tradeline id.'

    get "List a tradeline's deposits" do
      tags 'Deposits'
      operationId 'listDeposits'
      description <<~MD
        Returns the tradeline's deposits ordered by `deposit_date`, then id. Paginated — see the pagination
        headers. **Role:** `viewer` or higher.
      MD
      produces 'application/json'
      parameter '$ref' => '#/components/parameters/page'
      parameter '$ref' => '#/components/parameters/limit'

      response '200', 'A page of deposits' do
        paginated_headers
        schema type: :array, items: { '$ref' => '#/components/schemas/Deposit' }

        before do
          create(:deposit, tradeline: tradeline, amount: '100.00', deposit_date: '2026-12-15')
          create(:deposit, tradeline: tradeline, amount: '250.00', deposit_date: '2026-11-15')
        end

        run_test! do
          expect(json.pluck('deposit_date')).to eq(%w[2026-11-15 2026-12-15])
        end
      end

      response '404', 'Tradeline not found' do
        schema '$ref' => '#/components/schemas/NotFoundError'
        let(:tradeline_id) { 0 }
        run_test!
      end

      unauthorized_response
    end

    post 'Create a deposit' do
      tags 'Deposits'
      operationId 'createDeposit'
      description <<~MD
        Schedules a deposit against the tradeline and returns it with the tradeline's new outstanding balance.

        - `amount` must be greater than 0, have at most 2 decimal places, and be **no more than the current
          outstanding balance** (depositing exactly the remaining balance is allowed). The check is atomic,
          so concurrent requests can never overdraw the tradeline.
        - `deposit_date` must be `YYYY-MM-DD`.
        - Send an `Idempotency-Key` to make retries safe.

        The body may be flat or wrapped in `{"deposit": {…}}`. Deposits cannot be changed or deleted afterwards.
        Successful and rejected attempts are recorded in the audit log. **Role:** `operator` or `admin`.
      MD
      consumes 'application/json'
      produces 'application/json'
      parameter name: 'Idempotency-Key', in: :header, required: false,
                schema: { type: :string, maxLength: 255 },
                description: 'Unique key per intended deposit, e.g. a UUID such as ' \
                             '`6f1c2c9e-3f0a-4b8e-9a41-1d2f1b7c8e10`. A retry with the same key and body returns ' \
                             'the original deposit instead of creating a new one. Scoped per tradeline. ' \
                             'Use a new key for each new deposit.'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/DepositInput' }
      request_body_example value: { amount: '250.00', deposit_date: '2026-11-15' }, name: 'deposit',
                           summary: 'Schedule a deposit'
      request_body_example value: { amount: '5000.00', deposit_date: '2026-11-15' }, name: 'too_large',
                           summary: 'Exceeds the balance (422)'
      request_body_example value: { amount: '-1.005', deposit_date: '2026-02-30' }, name: 'invalid',
                           summary: 'Invalid input (422)'

      let(:Authorization) { bearer(:operator) }
      let(:body) { { amount: '250.00', deposit_date: '2026-11-15' } }

      response '201', 'Deposit created' do
        header 'location', schema: { type: :string }, description: 'URL of the new deposit.'
        schema '$ref' => '#/components/schemas/DepositWithBalance'
        run_test! do
          expect(json['tradeline_outstanding_balance']).to eq('750.00')
        end
      end

      response '200', 'Idempotent replay: this Idempotency-Key was already used with the same body' do
        header 'idempotent-replayed', schema: { type: :string, enum: ['true'] },
                                      description: 'Present when the original deposit is being returned.'
        schema '$ref' => '#/components/schemas/DepositWithBalance'
        let(:'Idempotency-Key') { 'order-42' }
        before do
          Deposits::Create.call(tradeline: tradeline, params: body, idempotency_key: 'order-42')
        end
        run_test! do
          expect(tradeline.deposits.count).to eq(1)
        end
      end

      response '400', 'Missing or malformed body' do
        schema '$ref' => '#/components/schemas/BadRequestError'
        let(:body) { {} }
        run_test!
      end

      response '404', 'Tradeline not found' do
        schema '$ref' => '#/components/schemas/NotFoundError'
        let(:tradeline_id) { 0 }
        run_test!
      end

      response '422', 'Rejected: invalid input, insufficient balance, or a reused Idempotency-Key' do
        schema '$ref' => '#/components/schemas/DepositError'
        example 'application/json', :insufficient_balance, {
          error: { code: 'insufficient_balance', message: 'Deposit exceeds the outstanding balance',
                   details: { amount: ['exceeds the outstanding balance of 750.00'] } }
        }, 'Deposit exceeds the outstanding balance'
        example 'application/json', :validation_failed, {
          error: { code: 'validation_failed', message: 'Deposit is invalid',
                   details: { amount: ['must be greater than 0', 'must have at most 2 decimal places'],
                              deposit_date: ['must be a valid date in YYYY-MM-DD format'] } }
        }, 'Invalid amount and date'
        example 'application/json', :idempotency_key_reused, {
          error: { code: 'idempotency_key_reused', message: 'Idempotency-Key was already used for a different deposit',
                   details: { idempotency_key: ['was already used with different parameters'] } }
        }, 'Idempotency-Key reused with a different body'

        let(:body) { { amount: '1000.01', deposit_date: '2026-11-15' } }
        run_test! do
          expect(json.dig('error', 'code')).to eq('insufficient_balance')
        end
      end

      unauthorized_response
      forbidden_response(:viewer)
    end
  end

  path '/tradelines/{tradeline_id}/deposits/{id}' do
    parameter name: :tradeline_id, in: :path, required: true, schema: { type: :integer }, description: 'Tradeline id.'
    parameter name: :id, in: :path, required: true, schema: { type: :integer }, description: 'Deposit id.'

    get 'Show a deposit' do
      tags 'Deposits'
      operationId 'getDeposit'
      description <<~MD
        Returns one deposit with its tradeline's current outstanding balance. Returns 404 if the deposit
        belongs to a different tradeline. **Role:** `viewer` or higher.
      MD
      produces 'application/json'

      let(:deposit) { create(:deposit, tradeline: tradeline, amount: '250.00', deposit_date: '2026-11-15') }
      let(:id) { deposit.id }

      response '200', 'The deposit' do
        schema '$ref' => '#/components/schemas/DepositWithBalance'
        run_test! do
          expect(json).to include('amount' => '250.00', 'tradeline_outstanding_balance' => '750.00')
        end
      end

      response '404', 'Deposit not found on this tradeline' do
        schema '$ref' => '#/components/schemas/NotFoundError'
        let(:id) { create(:deposit).id }
        run_test!
      end

      unauthorized_response
    end
  end
end
