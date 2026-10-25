require 'swagger_helper'

RSpec.describe 'Audit events', type: :request do
  path '/audit_events' do
    get 'List audit events' do
      tags 'Audit events'
      operationId 'listAuditEvents'
      description <<~MD
        Append-only audit trail, newest first. Each event records the acting API key, request id, IP address
        and user agent, plus event-specific metadata.

        | `action` | Recorded when |
        |---|---|
        | `tradeline.created` | An admin creates a tradeline |
        | `deposit.created` | A deposit is committed (in the same transaction) |
        | `deposit.rejected` | A deposit fails validation or the balance check |
        | `deposit.idempotent_replay` | A retry is answered with an existing deposit |
        | `authorization.denied` | A key attempts an action its role does not allow |

        Paginated — see the pagination headers. **Role:** `admin`.
      MD
      produces 'application/json'
      parameter name: :event, in: :query, required: false, description: 'Filter by action.',
                schema: { type: :string, enum: AuditEvent::ACTIONS }
      parameter name: :auditable_type, in: :query, required: false, description: 'Filter by record type.',
                schema: { type: :string, enum: %w[Tradeline Deposit] }
      parameter name: :auditable_id, in: :query, required: false, description: 'Filter by record id.',
                schema: { type: :integer }
      parameter name: :api_key_id, in: :query, required: false, description: 'Filter by acting API key.',
                schema: { type: :integer }
      parameter name: :request_id, in: :query, required: false,
                description: 'Filter by the `X-Request-Id` of the request that caused the event.',
                schema: { type: :string }
      parameter '$ref' => '#/components/parameters/page'
      parameter '$ref' => '#/components/parameters/limit'

      let(:Authorization) { bearer(:admin) }

      response '200', 'A page of audit events' do
        paginated_headers
        schema type: :array, items: { '$ref' => '#/components/schemas/AuditEvent' }

        let(:event) { 'deposit.created' }
        before do
          Current.api_key = ApiKey.issue!(name: 'payments-service', role: :operator).first
          tradeline = create(:tradeline, amount: '1000.00')
          Deposits::Create.call(tradeline: tradeline, params: { amount: '100.00', deposit_date: '2026-12-15' })
          Deposits::Create.call(tradeline: tradeline, params: { amount: '5000.00', deposit_date: '2026-12-15' })
        ensure
          Current.reset
        end

        run_test! do
          expect(json.size).to eq(1)
          expect(json.first).to include('action' => 'deposit.created')
          expect(json.first.dig('actor', 'role')).to eq('operator')
        end
      end

      unauthorized_response
      forbidden_response(:operator)
    end
  end
end
