# OpenAPI definition for the Deposits API.
#
# The paths are generated from the request specs in spec/docs, which run as
# part of `bundle exec rspec` and validate every documented response against
# the schemas below — so the published docs cannot drift from the real API.
#
# Regenerate swagger/v1/openapi.json after changing the docs specs:
#   bin/rails docs:generate
require 'rails_helper'

module ApiDocs
  MONEY = {
    type: :string, pattern: '^-?\d+\.\d{2}$', example: '3223.54',
    description: 'Decimal amount as a string with exactly two decimals.'
  }.freeze

  MONEY_INPUT = {
    type: :string, example: '250.00',
    description: 'Greater than 0, at most 2 decimal places, at most 999999.99. ' \
                 'A JSON number (e.g. `250.5`) is also accepted.'
  }.freeze

  TIMESTAMP = { type: :string, format: 'date-time', example: '2026-10-25T02:30:35.113Z' }.freeze

  DESCRIPTION = <<~MARKDOWN.freeze
    Record **future deposits** against **tradelines** (credit accounts such as a card or auto loan) and
    track each tradeline's **outstanding balance** — `amount` minus the sum of its deposits.

    ## Try it

    1. Get an API key. Locally, `bin/rails db:seed` prints one per role
       (`export ADMIN_TOKEN=dpx_…`); otherwise run `bin/rails "auth:create_key[my-name,admin]"`.
    2. Click **Authorize** (top right), paste the token (just the `dpx_…` value, no `Bearer` prefix) and confirm.
       It is remembered across page reloads in this browser.
    3. Open an endpoint, click **Try it out**, then **Execute**. Requests go to the server this page is served from.

    ## Authentication & roles

    Every endpoint except `GET /up` requires `Authorization: Bearer <api key>`.

    | Role | Read tradelines & deposits | Create deposits | Create tradelines | Read audit log |
    |---|:-:|:-:|:-:|:-:|
    | `viewer` | ✓ | | | |
    | `operator` | ✓ | ✓ | | |
    | `admin` | ✓ | ✓ | ✓ | ✓ |

    A missing, unknown, expired or revoked key returns **401**. A valid key whose role lacks the permission
    returns **403** (and the attempt is recorded in the audit log).

    ## Money

    Amounts are **strings with exactly two decimals** (`"3223.54"`) in every response, so they never pass
    through a lossy float. In requests, send a string (preferred) or a JSON number. Values with fractions of
    a cent are rejected, never rounded.

    ## Outstanding balance

    `outstanding_balance = amount − Σ deposits`. A deposit larger than the current outstanding balance is
    rejected with `422 insufficient_balance`; depositing exactly the remaining balance is allowed. The check
    is atomic, so concurrent requests can never overdraw a tradeline.

    ## Idempotency

    Send an `Idempotency-Key` header (e.g. a UUID) when creating a deposit. Retrying with the same key and body
    returns the original deposit with `200 OK` and `Idempotent-Replayed: true` instead of creating a duplicate.
    Reusing a key with a different body returns `422 idempotency_key_reused`.

    ## Pagination

    List endpoints take `page` (default 1) and `limit` (default 25, max 100) and return a plain JSON array.
    Pagination metadata is in the response headers: `Link` (RFC 8288 `first`/`prev`/`next`/`last`),
    `Current-Page`, `Page-Items`, `Total-Pages` and `Total-Count`. A page past the end returns `[]`.

    ## Errors

    Every error has the same shape:

    ```json
    { "error": { "code": "validation_failed", "message": "Deposit is invalid",
                 "details": { "amount": ["must be greater than 0"] } } }
    ```

    | Status | `code` | Meaning |
    |---|---|---|
    | 400 | `bad_request` | Malformed JSON, missing body, invalid `page`/`limit` |
    | 401 | `unauthorized` | Missing or invalid API key |
    | 403 | `forbidden` | The key's role does not allow this action |
    | 404 | `not_found` | Unknown tradeline, or a deposit that does not belong to it |
    | 422 | `validation_failed` | Invalid fields — all errors are returned at once in `details` |
    | 422 | `insufficient_balance` | Deposit exceeds the outstanding balance |
    | 422 | `idempotency_key_reused` | Same `Idempotency-Key`, different request |
    | 422 | `tradeline_amount_missing` | Legacy tradeline without an amount |
    | 429 | `rate_limited` | Too many requests; see `Retry-After` |

    ## Rate limits

    300 requests/min per API key, 20/min per IP for requests without credentials, 1000/min per IP overall.

    ## Tracing

    Every response has an `X-Request-Id` header. The same id is stored on audit events and in the request
    logs — include it when reporting a problem.
  MARKDOWN

  def self.error_schema(codes)
    {
      type: :object,
      additionalProperties: false,
      required: %w[error],
      properties: {
        error: {
          type: :object,
          additionalProperties: false,
          required: %w[code message],
          properties: {
            code: { type: :string, enum: codes },
            message: { type: :string },
            details: {
              type: :object,
              description: 'Field name → list of messages (validation errors only).',
              additionalProperties: { type: :array, items: { type: :string } }
            }
          }
        }
      }
    }
  end

  PAGINATION_HEADERS = {
    'link' => { schema: { type: :string },
                description: 'RFC 8288 links: `rel="first"`, `"prev"`, `"next"`, `"last"`.' },
    'current-page' => { schema: { type: :string }, description: 'Current page number.' },
    'page-items' => { schema: { type: :string }, description: 'Items per page (the effective `limit`).' },
    'total-pages' => { schema: { type: :string }, description: 'Number of pages.' },
    'total-count' => { schema: { type: :string }, description: 'Total number of items.' }
  }.freeze
end

RSpec.configure do |config|
  config.openapi_root = Rails.root.join('swagger').to_s
  config.openapi_format = :json

  # Fail the doc specs when a response contains a property the schema doesn't document.
  config.openapi_no_additional_properties = true

  config.openapi_specs = {
    'v1/openapi.json' => {
      openapi: '3.0.3',
      info: {
        title: 'Deposits API',
        version: 'v1',
        description: ApiDocs::DESCRIPTION
      },
      # Replaced at request time with the host serving the docs (config/initializers/rswag.rb),
      # so "Try it out" works on any port or domain.
      servers: [{ url: 'http://localhost:3000', description: 'Local development' }],
      security: [{ bearer_auth: [] }],
      tags: [
        { name: 'Tradelines', description: 'Credit accounts and their outstanding balance.' },
        { name: 'Deposits', description: 'Scheduled deposits against a tradeline. Deposits are immutable.' },
        { name: 'Audit events', description: 'Append-only record of money- and security-relevant actions (admin only).' },
        { name: 'Health', description: 'Liveness probe for load balancers.' }
      ],
      paths: {},
      components: {
        securitySchemes: {
          bearer_auth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: 'API key (dpx_…)',
            description: 'API key issued with `bin/rails "auth:create_key[name,role]"`. Paste the token only.'
          }
        },
        parameters: {
          page: {
            name: :page, in: :query, required: false,
            description: 'Page number (1-based).',
            schema: { type: :integer, minimum: 1, default: 1 }
          },
          limit: {
            name: :limit, in: :query, required: false,
            description: 'Items per page.',
            schema: { type: :integer, minimum: 1, maximum: 100, default: 25 }
          }
        },
        schemas: {
          Tradeline: {
            type: :object,
            additionalProperties: false,
            required: %w[id name amount deposits_total outstanding_balance created_at updated_at],
            properties: {
              id: { type: :integer, example: 4 },
              name: { type: :string, example: 'Visa Gold' },
              amount: ApiDocs::MONEY.merge(nullable: true, example: '1000.00',
                                           description: 'Total amount owed. `null` only for legacy records.'),
              deposits_total: ApiDocs::MONEY.merge(example: '350.00', description: 'Sum of all deposits.'),
              outstanding_balance: ApiDocs::MONEY.merge(
                nullable: true, example: '650.00',
                description: '`amount − deposits_total`. `null` when the tradeline has no amount.'
              ),
              created_at: ApiDocs::TIMESTAMP,
              updated_at: ApiDocs::TIMESTAMP
            }
          },
          TradelineInput: {
            type: :object,
            required: %w[name amount],
            properties: {
              name: { type: :string, maxLength: 255, example: 'Visa Gold' },
              amount: ApiDocs::MONEY_INPUT.merge(example: '1000.00',
                                                 description: 'At least 0, at most 2 decimal places, at most 999999.99.')
            }
          },
          Deposit: {
            type: :object,
            additionalProperties: false,
            required: %w[id tradeline_id amount deposit_date created_at],
            properties: {
              id: { type: :integer, example: 1 },
              tradeline_id: { type: :integer, example: 4 },
              amount: ApiDocs::MONEY.merge(example: '250.00'),
              deposit_date: { type: :string, format: :date, example: '2026-11-15',
                              description: 'Date the deposit is scheduled for.' },
              created_at: ApiDocs::TIMESTAMP
            }
          },
          DepositWithBalance: {
            type: :object,
            additionalProperties: false,
            required: %w[id tradeline_id amount deposit_date created_at tradeline_outstanding_balance],
            properties: {
              id: { type: :integer, example: 1 },
              tradeline_id: { type: :integer, example: 4 },
              amount: ApiDocs::MONEY.merge(example: '250.00'),
              deposit_date: { type: :string, format: :date, example: '2026-11-15' },
              created_at: ApiDocs::TIMESTAMP,
              tradeline_outstanding_balance: ApiDocs::MONEY.merge(
                nullable: true, example: '750.00', description: "The tradeline's outstanding balance now."
              )
            }
          },
          DepositInput: {
            type: :object,
            required: %w[amount deposit_date],
            properties: {
              amount: ApiDocs::MONEY_INPUT.merge(
                description: 'Greater than 0, at most 2 decimal places, and no more than the outstanding balance. ' \
                             'A JSON number is also accepted.'
              ),
              deposit_date: {
                type: :string, format: :date, example: '2026-11-15',
                description: 'Strict ISO 8601 `YYYY-MM-DD`. Usually a future date; past dates are allowed.'
              }
            }
          },
          AuditEvent: {
            type: :object,
            additionalProperties: false,
            required: %w[id action auditable_type auditable_id metadata request_id ip_address user_agent created_at actor],
            properties: {
              id: { type: :integer, example: 7 },
              action: {
                type: :string,
                enum: %w[tradeline.created deposit.created deposit.rejected deposit.idempotent_replay authorization.denied],
                example: 'deposit.created'
              },
              auditable_type: { type: :string, nullable: true, enum: ['Tradeline', 'Deposit', nil], example: 'Deposit' },
              auditable_id: { type: :integer, nullable: true, example: 2 },
              metadata: {
                type: :object, additionalProperties: true,
                description: 'Event details, e.g. amounts and balances before/after, or the rejection reason.',
                example: { tradeline_id: 4, amount: '100.00', deposit_date: '2026-12-15',
                           outstanding_balance_before: '750.00', outstanding_balance_after: '650.00' }
              },
              request_id: { type: :string, nullable: true, example: '4aa34462-e665-4db7-b1df-574967cefd63',
                            description: 'Matches the `X-Request-Id` response header and the request log line.' },
              ip_address: { type: :string, nullable: true, example: '203.0.113.7' },
              user_agent: { type: :string, nullable: true, example: 'curl/8.7.1' },
              created_at: ApiDocs::TIMESTAMP,
              actor: {
                type: :object, nullable: true, additionalProperties: false,
                description: 'The API key that performed the action.',
                required: %w[id name role token_prefix],
                properties: {
                  id: { type: :integer, example: 2 },
                  name: { type: :string, example: 'payments-service' },
                  role: { type: :string, enum: %w[viewer operator admin], example: 'operator' },
                  token_prefix: { type: :string, example: 'dpx_7Hq2xLm9',
                                  description: 'First 12 characters of the key, for identification.' }
                }
              }
            }
          },
          BadRequestError: ApiDocs.error_schema(%w[bad_request]),
          UnauthorizedError: ApiDocs.error_schema(%w[unauthorized]),
          ForbiddenError: ApiDocs.error_schema(%w[forbidden]),
          NotFoundError: ApiDocs.error_schema(%w[not_found]),
          ValidationError: ApiDocs.error_schema(%w[validation_failed]),
          DepositError: ApiDocs.error_schema(
            %w[validation_failed insufficient_balance idempotency_key_reused tradeline_amount_missing]
          ),
          RateLimitedError: ApiDocs.error_schema(%w[rate_limited])
        }
      }
    }
  }
end

# Shared building blocks for the doc specs.
module ApiDocsHelpers
  def unauthorized_response
    response '401', 'Missing or invalid API key' do
      header 'www-authenticate', schema: { type: :string }, description: '`Bearer realm="deposits"`'
      schema '$ref' => '#/components/schemas/UnauthorizedError'
      let(:Authorization) { 'Bearer dpx_invalid' }
      run_test!
    end
  end

  def forbidden_response(role)
    response '403', "The key's role does not allow this action" do
      schema '$ref' => '#/components/schemas/ForbiddenError'
      let(:Authorization) { bearer(role) }
      run_test!
    end
  end

  def paginated_headers
    ApiDocs::PAGINATION_HEADERS.each { |name, options| header name, **options }
  end
end

module ApiDocsExampleHelpers
  def bearer(role)
    "Bearer #{ApiKey.issue!(name: "docs-#{role}", role: role).last}"
  end
end

RSpec.configure do |config|
  config.extend ApiDocsHelpers, file_path: %r{spec/docs}
  config.include ApiDocsExampleHelpers, file_path: %r{spec/docs}
end
