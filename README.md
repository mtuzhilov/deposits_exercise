# Deposits API

A small Rails API for scheduling deposits against **tradelines** (accounts like a credit card or a car loan).
Each tradeline shows its **outstanding balance**: the amount owed minus all deposits.

**What it does**

- Add deposits to a tradeline, list them, and look one up.
- Show the outstanding balance on every tradeline.
- Refuse any deposit that's bigger than what's still owed, even if two requests arrive at the same moment.
- Return clear error messages when a request is wrong.
- Require an API key on every request, with three access levels.
- Keep a permanent log of who did what.

Curious how it works or why it's built this way? See **[design.md](design.md)**.

---

## Get started

You need Ruby 3.3 and Bundler.

```bash
git clone git@github.com:mtuzhilov/deposits_exercise.git
cd deposits_exercise
bundle install
bin/rails db:prepare
bin/rails server
```

The first time you run it, `db:prepare` creates the database, adds three sample tradelines and prints three API keys, one per access level:

```
export VIEWER_TOKEN=dpx_...
export OPERATOR_TOKEN=dpx_...
export ADMIN_TOKEN=dpx_...
```

Copy these lines into your terminal. Keys are shown only once. If you lose them, run `bin/rails db:seed` to get new ones.

## Try it in the browser

Open **http://localhost:3000/api-docs**.

1. Click **Authorize** and paste one of the keys (just the `dpx_…` part).
2. Open any endpoint and click **Try it out**.
3. Fill in the fields and click **Execute**.

The page lists every endpoint with examples of requests and responses.

## Try it with curl

Create a tradeline (admin key):

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Visa Gold","amount":"1000.00"}' localhost:3000/tradelines
```
```json
{"id":4,"name":"Visa Gold","amount":"1000.00","deposits_total":"0.00","outstanding_balance":"1000.00", ...}
```

Add a deposit (operator key):

```bash
curl -s -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -d '{"amount":"250.00","deposit_date":"2026-11-15"}' localhost:3000/tradelines/4/deposits
```
```json
{"id":1,"tradeline_id":4,"amount":"250.00","deposit_date":"2026-11-15", ...,"tradeline_outstanding_balance":"750.00"}
```

Try to deposit more than is owed:

```bash
curl -s -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -d '{"amount":"750.01","deposit_date":"2026-12-15"}' localhost:3000/tradelines/4/deposits
```
```json
{"error":{"code":"insufficient_balance","message":"Deposit exceeds the outstanding balance",
          "details":{"amount":["exceeds the outstanding balance of 750.00"]}}}
```

Send bad data:

```bash
curl -s -H "Authorization: Bearer $OPERATOR_TOKEN" -H "Content-Type: application/json" \
  -d '{"amount":"-5","deposit_date":"2026-02-30"}' localhost:3000/tradelines/4/deposits
```
```json
{"error":{"code":"validation_failed","message":"Deposit is invalid",
          "details":{"amount":["must be greater than 0"],
                     "deposit_date":["must be a valid date in YYYY-MM-DD format"]}}}
```

List deposits, look up one deposit, and check the balance (any key):

```bash
curl -s -H "Authorization: Bearer $VIEWER_TOKEN" localhost:3000/tradelines/4/deposits
curl -s -H "Authorization: Bearer $VIEWER_TOKEN" localhost:3000/tradelines/4/deposits/1
curl -s -H "Authorization: Bearer $VIEWER_TOKEN" localhost:3000/tradelines/4
```

## Endpoints

| Method | Path | Who can use it |
|---|---|---|
| `GET` | `/tradelines` | everyone |
| `GET` | `/tradelines/:id` | everyone |
| `POST` | `/tradelines` | admin |
| `GET` | `/tradelines/:id/deposits` | everyone |
| `GET` | `/tradelines/:id/deposits/:deposit_id` | everyone |
| `POST` | `/tradelines/:id/deposits` | operator, admin |
| `GET` | `/audit_events` | admin |
| `GET` | `/up` | no key needed (health check) |

Good to know:

- **Money** is always sent back as text with two decimals, like `"250.00"`. You can send amounts as text or as numbers.
- **Dates** use the `YYYY-MM-DD` format.
- **Long lists** come back 25 at a time. Use `?page=2` and `?limit=50` (maximum 100) to page through them. The total count is in the `Total-Count` response header.
- **Retrying safely:** add an `Idempotency-Key` header (any unique value, like a UUID) when creating a deposit. If the request is sent twice, only one deposit is created.

## API keys and access levels

| Level | Can do |
|---|---|
| **viewer** | Read tradelines and deposits |
| **operator** | Everything a viewer can do, plus create deposits |
| **admin** | Everything, plus create tradelines and read the audit log |

Manage keys from the terminal:

```bash
bin/rails "auth:create_key[billing-service,operator]"   # create a key (it's shown once)
bin/rails auth:list_keys                                # list keys (never shows the secret)
bin/rails "auth:revoke_key[dpx_AbCdEfGh]"               # turn a key off, using the start of the key
```

## Errors

Every error looks the same:

```json
{"error":{"code":"...","message":"...","details":{"field":["what's wrong"]}}}
```

| Status | Means |
|---|---|
| 400 | The request body is broken or missing |
| 401 | No API key, or the key is wrong, expired or revoked |
| 403 | The key isn't allowed to do this |
| 404 | The tradeline or deposit doesn't exist |
| 422 | The data isn't valid, or the deposit is more than what's owed |
| 429 | Too many requests; wait and try again |

## Run the tests

```bash
bundle exec rspec    # 255 tests: models, endpoints, docs, permissions, concurrency
bin/integration      # starts the server and runs 12 tests over real HTTP
```

GitHub Actions runs both on every push.

If you change the files in `spec/docs/`, run `bin/rails docs:generate` to update the API docs page.

## Where things are

| Path | What's there |
|---|---|
| `app/services/deposits/create.rb` | The rules for creating a deposit |
| `app/models/` | Tradeline, Deposit, ApiKey, AuditEvent |
| `app/controllers/` | Endpoints, plus sign-in, permission and error handling |
| `spec/` | Tests (`spec/docs` also produces the API docs) |
| `swagger/v1/openapi.json` | The API description behind `/api-docs` |
| [design.md](design.md) | How it works and why |

---

<details>
<summary><strong>The original assignment</strong></summary>

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

</details>
