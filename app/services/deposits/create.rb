module Deposits
  # Creates a deposit against a tradeline without ever letting the sum of
  # deposits exceed the tradeline amount — even under concurrent requests.
  #
  # The balance check and the reservation happen in one conditional UPDATE:
  #
  #   UPDATE tradelines SET deposits_total = deposits_total + :amount
  #   WHERE id = :id AND amount - deposits_total >= :amount
  #
  # The database evaluates the condition and applies the write atomically, so
  # two racing requests cannot both pass a stale "is there enough balance?"
  # read. This works identically on SQLite, PostgreSQL and MySQL and needs no
  # row locks (SQLite ignores SELECT ... FOR UPDATE anyway).
  class Create
    Result = Struct.new(:deposit, :status, :error_code, :message, :errors, :replayed, keyword_init: true) do
      def success?
        error_code.nil?
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(tradeline:, params:, idempotency_key: nil)
      @tradeline = tradeline
      @params = params
      @idempotency_key = idempotency_key
    end

    def call
      existing = find_by_idempotency_key
      return replay(existing) if existing

      deposit = Deposit.new(**@params.to_h.symbolize_keys, tradeline: @tradeline, idempotency_key: @idempotency_key)
      return validation_failed(deposit) unless deposit.valid?
      return no_amount(deposit) if @tradeline.amount.nil?

      created = Deposit.transaction do
        next false unless reserve_balance(deposit.amount)

        deposit.save!
        # Read inside the transaction (after our write) so the figures are
        # exact even when other deposits are being made concurrently.
        balance_after = @tradeline.reload.outstanding_balance
        AuditEvent.record!("deposit.created", auditable: deposit, metadata: {
          tradeline_id: @tradeline.id,
          amount: MoneyAttribute.format(deposit.amount),
          deposit_date: deposit.deposit_date.iso8601,
          outstanding_balance_before: MoneyAttribute.format(balance_after + deposit.amount),
          outstanding_balance_after: MoneyAttribute.format(balance_after),
          idempotency_key: @idempotency_key
        }.compact)
        true
      end

      created ? success(deposit) : insufficient_balance(deposit)
    rescue ActiveRecord::RecordNotUnique
      # Another request with the same idempotency key won the race; its
      # transaction (including the balance reservation) committed, ours did not.
      existing = find_by_idempotency_key
      raise unless existing

      replay(existing)
    end

    private

    def reserve_balance(amount)
      # SQLite stores decimals as floating point, so compare in integer cents
      # and keep the running total rounded to 2 places to avoid drift.
      Tradeline
        .where(id: @tradeline.id)
        .where.not(amount: nil)
        .where("ROUND(amount * 100) - ROUND(deposits_total * 100) >= ?", (amount * 100).to_i)
        .update_all(["deposits_total = ROUND(deposits_total + ?, 2), updated_at = ?", amount, Time.current]) == 1
    end

    def find_by_idempotency_key
      return if @idempotency_key.blank?

      @tradeline.deposits.find_by(idempotency_key: @idempotency_key)
    end

    def replay(existing)
      candidate = Deposit.new(@params.to_h)
      unless candidate.amount == existing.amount && candidate.deposit_date == existing.deposit_date
        return failure(existing, "idempotency_key_reused",
                       "Idempotency-Key was already used for a different deposit",
                       { idempotency_key: ["was already used with different parameters"] })
      end

      AuditEvent.record!("deposit.idempotent_replay", auditable: existing,
                                                      metadata: { idempotency_key: @idempotency_key })
      @tradeline.reload
      Result.new(deposit: existing, status: :ok, replayed: true)
    end

    def success(deposit)
      Result.new(deposit: deposit, status: :created, replayed: false)
    end

    def validation_failed(deposit)
      failure(deposit, "validation_failed", "Deposit is invalid", deposit.errors.to_hash)
    end

    def no_amount(deposit)
      failure(deposit, "tradeline_amount_missing", "Tradeline has no amount, so deposits cannot be accepted",
              { tradeline: ["has no amount set"] })
    end

    def insufficient_balance(deposit)
      balance = @tradeline.reload.outstanding_balance
      failure(deposit, "insufficient_balance", "Deposit exceeds the outstanding balance",
              { amount: ["exceeds the outstanding balance of #{MoneyAttribute.format(balance)}"] },
              outstanding_balance: MoneyAttribute.format(balance))
    end

    def failure(deposit, code, message, errors, **extra)
      AuditEvent.record!("deposit.rejected", auditable: @tradeline, metadata: {
        reason: code,
        errors: errors,
        requested_amount: deposit.amount_before_type_cast&.to_s,
        requested_deposit_date: deposit.deposit_date_before_type_cast&.to_s,
        idempotency_key: @idempotency_key,
        **extra
      }.compact)
      Result.new(deposit: deposit, status: :unprocessable_entity, error_code: code, message: message, errors: errors)
    end
  end
end
