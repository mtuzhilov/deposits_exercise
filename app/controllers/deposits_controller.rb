class DepositsController < ApplicationController
  # Authorize before loading the tradeline so callers without access cannot
  # probe which tradeline ids exist.
  require_permission :read_deposits, only: %i[index show]
  require_permission :create_deposit, only: :create
  before_action :set_tradeline

  def index
    @deposits = paginate(@tradeline.deposits)
  end

  def show
    @deposit = @tradeline.deposits.find(params[:id])
  end

  def create
    result = Deposits::Create.call(
      tradeline: @tradeline,
      params: deposit_params,
      idempotency_key: request.headers["Idempotency-Key"].presence
    )

    if result.success?
      @deposit = result.deposit
      response.headers["Idempotent-Replayed"] = "true" if result.replayed
      render :show, status: result.status, location: tradeline_deposit_url(@tradeline, @deposit)
    else
      render_error(result.status, result.error_code, result.message, result.errors)
    end
  end

  private

  def set_tradeline
    @tradeline = Tradeline.find(params[:tradeline_id])
  end

  def deposit_params
    params.require(:deposit).permit(:amount, :deposit_date)
  end
end
