# Deposits Exercise


## Requirements

A tradeline on a credit report represents an account, such as a credit card or car loan.

In the codebase, the following exists:

* The `Tradeline` model, which can be used to store tradelines in the database.
* A `Tradeline` controller, which serves both the `index` and `show` routes for tradelines.
* Basic `rspec` tests on the controller with a `tradeline` FactoryBot.

Add in the ability to create deposits for a specific tradeline using a JSON API call. You should store the deposit date (this is most likely a future date), and amount. Expose the outstanding balance for a given tradeline in the JSON output for `TradelinesController#show`, and `TradelinesController#index`. The oustanding balance should be calculated as the `amount` minus all of the deposit amounts.

In addition:

* A deposit should not be able to be created that exceeds the outstanding balance of a tradeline.
* You should return validation errors if a deposit cannot be created.
* Expose endpoints for seeing all deposits for a given tradeline, as well as seeing an individual deposit.

Feel free to add any gems to the `Gemfile`, and touch any of the existing code. For example, if you prefer to use PostgreSQL or MySQL over the included SQLite, or a serializer of your choice, please go ahead. This is not required, but you can be as creative as you want.

This exercise is purely API based, and will not have any frontend components. Please do not spend more than 3 hours on this.

## Setup

The exercise requires Ruby 3.3.0. Simply clone the repo, and run `bundle` to get started. This will install Rails 7.1.2, and the other specified gems.

## Submission

Please do not fork the repo; if forked accidentally, please delete the fork. For review, either of the following methods for submission are preferred:

* Cloning the repository and then uploading it under your Github account for review.
* Zipping up the directory. 
---

# Solution

A JSON API for recording future deposits against tradelines. It has authentication, role-based access, an append-only audit trail, and an outstanding balance that **can't be overdrawn, even by concurrent requests**.

- [Quick start](#quick-start)
- [Authentication & roles](#authentication--roles)
- [API reference](#api-reference)
- [Walkthrough with curl](#walkthrough-with-curl)
- [Running the tests](#running-the-tests)
- [Design decisions](#design-decisions)
- [Audit trail & logging](#audit-trail--logging)
- [Production considerations & future work](#production-considerations--future-work)

## Quick start

Requirements: Ruby 3.3.x (the Gemfile accepts any 3.3 patch release) and Bundler. SQLite ships with the `sqlite3` gem.

```bash
git clone git@github.com:mtuzhilov/deposits_exercise.git
cd deposits_exercise
bundle install
bin/rails db:prepare     # creates the database, loads the schema, runs db/seeds.rb
```

The seed step creates three sample tradelines and **one API key per role**, and prints the tokens. Copy those `export` lines into your shell:

```
Development API keys (shown once):
  export VIEWER_TOKEN=dpx_...
  export OPERATOR_TOKEN=dpx_...
  export ADMIN_TOKEN=dpx_...
```

> Tokens are stored only as SHA-256 digests, so they can't be shown again. Run `bin/rails db:seed` again to issue a fresh set (this revokes the previous seed keys).

Start the server:

```bash
bin/rails server         # http://localhost:3000
curl -s localhost:3000/up   # health check, no auth required
```

## Authentication & roles

Every endpoint except `GET /up` requires an API key, sent as a bearer token:

```
Authorization: Bearer dpx_6Qm...
```

**Why API keys?** This is a machine-to-machine API (other services record deposits). Per-client API keys can be revoked instantly and audited per client, and need no extra infrastructure. Sessions/cookies would be the wrong fit, and self-signed JWTs can't be revoked before they expire.

- Tokens are `dpx_` + 256 random bits. Only a **SHA-256 digest** is stored, so a database leak doesn't leak usable credentials. A fast hash is enough (no bcrypt needed) because the tokens are high-entropy rather than human-chosen passwords, and it keeps authentication to a single indexed lookup.
- The first 12 characters (`token_prefix`) are stored to identify a key in logs, audit records and listings.
- Keys can **expire** (`expires_at`) and be **revoked** (`revoked_at`). `last_used_at` is tracked, throttled to one write per minute.
- Unknown, expired and revoked keys all get the same `401` response with `WWW-Authenticate: Bearer`, so a caller can't tell which check failed.
- Tokens are not accepted in query strings, where they would end up in access logs.

### Roles

| Role       | Read tradelines & deposits | Create deposits | Create tradelines | Read audit log |
|------------|:--:|:--:|:--:|:--:|
| `viewer`   | ✓ |   |   |   |
| `operator` | ✓ | ✓ |   |   |
| `admin`    | ✓ | ✓ | ✓ | ✓ |

An authenticated key without permission gets `403 forbidden`, and the attempt is recorded in the audit log. Permissions are checked **before** the tradeline is loaded, so an unauthorized caller can't probe which IDs exist. The role → permission map is `ApiKey::PERMISSIONS`.

### Managing keys

```bash
bin/rails "auth:create_key[payments-service,operator]"          # prints the token once
EXPIRES_IN_DAYS=30 bin/rails "auth:create_key[contractor,viewer]"
bin/rails auth:list_keys                                         # prefix, role, status, last used — never the token
bin/rails "auth:revoke_key[dpx_6QmZk2Lp]"                        # by prefix; takes effect immediately
```

## API reference

All responses are JSON. **Money is always a string with exactly two decimals** (`"3223.54"`), so clients never parse it into a lossy float. Money can be sent as a string or a JSON number.

| Method | Path | Role | Description |
|---|---|---|---|
| `GET`  | `/up` | none | Health check |
| `GET`  | `/tradelines` | viewer | List tradelines with `outstanding_balance` (paginated) |
| `GET`  | `/tradelines/:id` | viewer | Show one tradeline with `outstanding_balance` |
| `POST` | `/tradelines` | admin | Create a tradeline: `{"name": "...", "amount": "1000.00"}` |
| `GET`  | `/tradelines/:tradeline_id/deposits` | viewer | List a tradeline's deposits, by `deposit_date` (paginated) |
| `GET`  | `/tradelines/:tradeline_id/deposits/:id` | viewer | Show one deposit |
| `POST` | `/tradelines/:tradeline_id/deposits` | operator | Create a deposit: `{"amount": "250.00", "deposit_date": "2026-11-15"}` |
| `GET`  | `/audit_events` | admin | Audit log, newest first (paginated, filterable) |

Request bodies can be flat (`{"amount": ...}`) or wrapped (`{"deposit": {"amount": ...}}`).

**Tradeline**

```json
{ "id": 4, "name": "Visa Gold", "amount": "1000.00", "deposits_total": "350.00",
  "outstanding_balance": "650.00", "created_at": "...", "updated_at": "..." }
```

`outstanding_balance = amount − sum(deposits)`. It's `null` only for legacy tradelines that have no amount.

**Deposit**

```json
{ "id": 1, "tradeline_id": 4, "amount": "250.00", "deposit_date": "2026-11-15",
  "created_at": "...", "tradeline_outstanding_balance": "650.00" }
```

(`tradeline_outstanding_balance` is included on show and create responses.)

**Deposit rules**

- `amount`: required, `> 0`, at most 2 decimal places (`10.005` is rejected, not silently rounded), at most `999999.99`, and **at most the tradeline's current outstanding balance**. Depositing the exact remaining balance is allowed.
- `deposit_date`: required, strict ISO 8601 `YYYY-MM-DD`. Impossible dates (`2026-02-30`) and ambiguous formats (`10/11/2026`) are rejected. Future dates are the expected case. Past dates are allowed too (back-dated entries), since the requirements don't forbid them.
- Deposits are **immutable**: there are no update or delete endpoints, and the model is read-only once persisted.

**Idempotency.** Send an `Idempotency-Key` header (any unique string up to 255 characters, e.g. a UUID) with `POST .../deposits`. If the request is retried with the same key and body, the original deposit comes back with `200 OK` and `Idempotent-Replayed: true` instead of creating a second one. Reusing a key with a *different* body returns `422 idempotency_key_reused`. Keys are scoped per tradeline.

**Pagination.** `?page=N&limit=M` (default 25, max 100). Metadata goes in the headers, so bodies stay plain arrays: `Link` (RFC 8288 `first`/`prev`/`next`/`last`), `Current-Page`, `Page-Items`, `Total-Pages`, `Total-Count`.

**Audit log filters.** `?event=deposit.created`, `?auditable_type=Deposit&auditable_id=12`, `?api_key_id=3`, `?request_id=...`.

### Errors

Every error has the same shape:

```json
{ "error": { "code": "validation_failed", "message": "Deposit is invalid",
             "details": { "amount": ["must be greater than 0"] } } }
```

| Status | `code` | When |
|---|---|---|
| 400 | `bad_request` | Malformed JSON, missing body, invalid `page`/`limit` |
| 401 | `unauthorized` | Missing, unknown, expired or revoked API key |
| 403 | `forbidden` | The key's role doesn't allow the action |
| 404 | `not_found` | Unknown tradeline, or a deposit that doesn't belong to that tradeline |
| 422 | `validation_failed` | Invalid fields (all errors are returned at once) |
| 422 | `insufficient_balance` | The deposit exceeds the outstanding balance |
| 422 | `idempotency_key_reused` | Same `Idempotency-Key`, different request |
| 422 | `tradeline_amount_missing` | Legacy tradeline without an amount |
| 429 | `rate_limited` | Too many requests (see `Retry-After`) |

## Walkthrough with curl

With the server running and the three `*_TOKEN` variables exported (see [Quick start](#quick-start)). The output below is from a real run.

**1. No token → 401**

```bash
curl -s localhost:3000/tradelines
```
```json
{"error":{"code":"unauthorized","message":"A valid API key is required"}}
```

**2. Admin creates a tradeline**

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Visa Gold","amount":"1000.00"}' localhost:3000/tradelines
```
```json
{"id":4,"name":"Visa Gold","amount":"1000.00","deposits_total":"0.00","outstanding_balance":"1000.00","created_at":"...","updated_at":"..."}
```

**3. Operator creates a deposit (with an idempotency key)**

```bash
curl -s -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -H "Idempotency-Key: 7b1c-0001" \
  -d '{"amount":"250.00","deposit_date":"2026-11-15"}' localhost:3000/tradelines/4/deposits
```
```json
{"id":1,"tradeline_id":4,"amount":"250.00","deposit_date":"2026-11-15","created_at":"...","tradeline_outstanding_balance":"750.00"}
```

**4. The same request retried → same deposit, no double charge**

```bash
curl -s -i -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -H "Idempotency-Key: 7b1c-0001" \
  -d '{"amount":"250.00","deposit_date":"2026-11-15"}' localhost:3000/tradelines/4/deposits
```
```
HTTP/1.1 200 OK
idempotent-replayed: true

{"id":1,"tradeline_id":4,"amount":"250.00","deposit_date":"2026-11-15","created_at":"...","tradeline_outstanding_balance":"750.00"}
```

**5. A deposit that exceeds the outstanding balance → 422**

```bash
curl -s -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -d '{"amount":"750.01","deposit_date":"2026-12-15"}' localhost:3000/tradelines/4/deposits
```
```json
{"error":{"code":"insufficient_balance","message":"Deposit exceeds the outstanding balance","details":{"amount":["exceeds the outstanding balance of 750.00"]}}}
```

**6. Invalid input → every validation error at once**

```bash
curl -s -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -d '{"amount":"-1.005","deposit_date":"2026-02-30"}' localhost:3000/tradelines/4/deposits
```
```json
{"error":{"code":"validation_failed","message":"Deposit is invalid","details":{"amount":["must be greater than 0","must have at most 2 decimal places"],"deposit_date":["must be a valid date in YYYY-MM-DD format"]}}}
```

**7. A viewer can't create deposits → 403**

```bash
curl -s -H "Authorization: Bearer $VIEWER_TOKEN" -H "Content-Type: application/json" \
  -d '{"amount":"10.00","deposit_date":"2026-12-15"}' localhost:3000/tradelines/4/deposits
```
```json
{"error":{"code":"forbidden","message":"This API key is not allowed to perform this action"}}
```

**8. A second deposit, then list and show**

```bash
curl -s -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -d '{"amount":"100.00","deposit_date":"2026-12-15"}' localhost:3000/tradelines/4/deposits

curl -s -H "Authorization: Bearer $VIEWER_TOKEN" localhost:3000/tradelines/4/deposits
```
```json
[{"id":1,"tradeline_id":4,"amount":"250.00","deposit_date":"2026-11-15","created_at":"..."},
 {"id":2,"tradeline_id":4,"amount":"100.00","deposit_date":"2026-12-15","created_at":"..."}]
```
```bash
curl -s -H "Authorization: Bearer $VIEWER_TOKEN" localhost:3000/tradelines/4/deposits/1
```
```json
{"id":1,"tradeline_id":4,"amount":"250.00","deposit_date":"2026-11-15","created_at":"...","tradeline_outstanding_balance":"650.00"}
```

**9. The outstanding balance on the tradeline (show and index)**

```bash
curl -s -H "Authorization: Bearer $VIEWER_TOKEN" localhost:3000/tradelines/4
```
```json
{"id":4,"name":"Visa Gold","amount":"1000.00","deposits_total":"350.00","outstanding_balance":"650.00","created_at":"...","updated_at":"..."}
```
```bash
curl -s -i -H "Authorization: Bearer $VIEWER_TOKEN" "localhost:3000/tradelines?limit=2"
```
```
link: <http://localhost:3000/tradelines?limit=2&page=1>; rel="first", <http://localhost:3000/tradelines?limit=2&page=2>; rel="next", <http://localhost:3000/tradelines?limit=2&page=2>; rel="last"
current-page: 1
page-items: 2
total-pages: 2
total-count: 4

[{"id":1,"name":"Visa Platinum Credit Card","amount":"3223.54","deposits_total":"0.00","outstanding_balance":"3223.54",...},
 {"id":2,"name":"Auto Loan","amount":"18500.00","deposits_total":"0.00","outstanding_balance":"18500.00",...}]
```

**10. An admin reviews the audit trail**

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" "localhost:3000/audit_events?event=deposit.created&limit=1"
```
```json
[{"id":7,"action":"deposit.created","auditable_type":"Deposit","auditable_id":2,
  "metadata":{"tradeline_id":4,"amount":"100.00","deposit_date":"2026-12-15",
              "outstanding_balance_before":"750.00","outstanding_balance_after":"650.00"},
  "request_id":"4aa34462-e665-4db7-b1df-574967cefd63","ip_address":"::1","user_agent":"curl/8.7.1",
  "created_at":"...","actor":{"id":2,"name":"dev-seed-operator","role":"operator","token_prefix":"dpx_7Hq2xLm9"}}]
```

## Running the tests

### Unit, model and request specs

```bash
bundle exec rspec
```

221 examples, covering:

- **Models**: every validation edge case (zero/negative/non-numeric/fractional-cent amounts, invalid and ambiguous dates, max column size), the DB check constraints, immutability, `outstanding_balance`, reconciliation, API key digest/expiry/revocation, and the role permission matrix.
- **`Deposits::Create`**: exact-balance deposits, overdraw rejection with no side effects, floating-point edge cases (`3223.54 − 3000.00`), idempotent replay and key reuse, and **real multi-threaded concurrency tests** that prove the balance can't be overdrawn and that concurrent retries with one idempotency key create exactly one deposit.
- **Requests**: every endpoint, status code and error shape, pagination, and N+1 protection. 401s are tested on *every route discovered from the route table*, so a new endpoint can't skip auth by accident. A full role × endpoint authorization matrix, audit contents, rate limiting and the rake tasks are covered too.

A coverage report is written to `coverage/index.html` (about 99% line, 93% branch).

### Live integration tests (real HTTP)

`spec/integration` exercises a **running server** over HTTP, without loading Rails or touching the database. It checks every assignment requirement end to end, plus idempotency, 10 concurrent deposits against one tradeline (exactly 6 succeed, and the balance never goes negative), and the auth/role/audit behaviour.

```bash
bin/integration
```

The script prepares the database, boots a server on port 3999, waits for `/up`, issues three short-lived API keys (one per role, expiring after 1 hour), runs the suite, and shuts the server down. To target a server you already started:

```bash
BASE_URL=http://localhost:3000 bin/integration
```

These tests are tagged `:integration` and excluded from a plain `bundle exec rspec` run. CI (`.github/workflows/ci.yml`) runs both suites on every push.

## Design decisions

### Balance enforcement that holds under concurrency

The obvious implementation (`if deposit.amount <= tradeline.outstanding_balance then save`) is a **check-then-act race**: two concurrent requests can both read a balance of 100, both deposit 100, and overdraw the account. Instead, `Deposits::Create` reserves the balance with a single conditional `UPDATE`, in the same transaction as the insert:

```sql
UPDATE tradelines
SET    deposits_total = ROUND(deposits_total + :amount, 2)
WHERE  id = :id
  AND  amount IS NOT NULL
  AND  ROUND(amount * 100) - ROUND(deposits_total * 100) >= :amount_in_cents
```

If no row is updated, the deposit would exceed the balance and is rejected. The database evaluates the condition and applies the write atomically, so this is race-free on SQLite, PostgreSQL and MySQL without `SELECT … FOR UPDATE` (which SQLite doesn't support).

- `tradelines.deposits_total` is a cached running total, so `outstanding_balance` is O(1) and `GET /tradelines` needs no `SUM`/N+1 per row.
- **Database CHECK constraints** are a last line of defence even if application code is bypassed: `deposits.amount > 0`, `deposits_total >= 0`, `deposits_total <= amount`.
- `bin/rails deposits:reconcile` compares every cached total against `SUM(deposits.amount)` and exits non-zero on drift, so it can be scheduled as a monitor. `FIX=1` repairs drift.
- The comparison is done in **integer cents** because SQLite stores decimals as floating point (`3223.54 − 3000.00 = 223.53999…`). There's a test for this.

### Money

`decimal(8,2)` columns and `BigDecimal` end to end, never `Float`. Input with fractions of a cent is **rejected rather than rounded**, since rounding money silently is a bug. Output is a fixed 2-decimal string.

### SQLite and threads

While writing the concurrency tests I found that Rails 7.1's SQLite adapter waits for the write lock with `busy_timeout`, which sleeps **while holding Ruby's GVL**. The thread that holds the lock then can't run to commit, and concurrent Puma requests fail with `database is locked`. `config/initializers/sqlite_busy_handler.rb` backports the fix Rails 8 adopted: a Ruby-level busy handler that releases the GVL between retries. It's not needed on PostgreSQL.

### Structure

- `Deposits::Create` (service object) owns the business transaction. Controllers stay thin.
- `ErrorHandling`, `Authentication` and `Authorization` are controller concerns. JSON is rendered with jbuilder partials.
- Deposits are nested under tradelines and always looked up through `tradeline.deposits`, so a deposit can't be read through the wrong tradeline.
- The app loads only the Rails frameworks it uses. Active Storage, Action Mailbox and Action Text are excluded because they mount public routes that would bypass API-key auth.

## Audit trail & logging

**`audit_events`** is an append-only table. Rows are read-only once written and can't be destroyed through the model.

| Action | Recorded when | Metadata |
|---|---|---|
| `tradeline.created` | an admin creates a tradeline | name, amount |
| `deposit.created` | a deposit is committed | amount, date, outstanding balance before/after, idempotency key |
| `deposit.rejected` | a deposit fails validation or the balance check | reason, errors, requested amount/date |
| `deposit.idempotent_replay` | a retried request is answered from an existing deposit | idempotency key |
| `authorization.denied` | an authenticated key attempts a forbidden action | permission, role, method, path |

Each event records the **actor** (API key), `request_id`, IP address and user agent. Successful writes are audited **in the same transaction** as the change, so there can never be a deposit without its audit record. Rejections and denials are kept for fraud review. Failed authentication (401) is *not* written to the database, so unauthenticated traffic can't flood the table. It shows up in the request logs instead.

**Structured request logs** (lograge) produce one JSON line per request, including the caller's key prefix and role:

```json
{"method":"GET","path":"/audit_events","format":"json","controller":"AuditEventsController","action":"index","status":200,"duration":3.77,"db":0.18,"request_id":"0ab8547b-...","ip":"::1","api_key":"dpx_9fK3wQz1","role":"admin","time":"2026-10-25T02:30:35.316Z"}
```

Every response carries an `X-Request-Id` header, and the same ID is stored on audit events, so a client's support ticket can be traced from the log line to the audit row. Tokens and `Authorization` values are filtered from logs.

**Rate limiting** (Rack::Attack): 300 requests/min per API key, 20/min per IP for requests without credentials, and 1000/min per IP overall. Over the limit, the response is `429` with `Retry-After`. `/up` is exempt. The limits are configurable with `RATE_LIMIT_PER_KEY`, `RATE_LIMIT_UNAUTHENTICATED` and `RATE_LIMIT_PER_IP`.

## Production considerations & future work

Done as part of this exercise: authentication, RBAC, an audit trail, idempotency, race-free balance enforcement, DB constraints, rate limiting, structured logs, a health check, `force_ssl` in production, and CI.

What I would do next for a real deployment:

- **PostgreSQL** for multi-process write concurrency, plus a Redis-backed Rack::Attack store so limits are shared across processes. The balance logic needs no changes.
- **Deposit lifecycle**: deposits are immutable today. Real money movement needs states (`scheduled → processing → settled / failed / cancelled`) and corrections via reversing entries, never edits or deletes.
- **Key management**: self-service key rotation with an overlap window, per-key scopes or IP allowlists, and possibly OAuth2 client credentials or mTLS for external partners.
- **Audit hardening**: ship audit events to write-once storage (or hash-chain them) so even a DB admin can't alter history. Add retention policies.
- **Multi-currency**: currently implicit single currency. Store an ISO 4217 code per tradeline and use integer minor units.
- **Observability**: metrics (deposit volume, rejection rate, 4xx/5xx), alerting on `deposits:reconcile` drift, and error tracking.
- **API docs**: an OpenAPI spec generated from the request specs (e.g. rswag).
