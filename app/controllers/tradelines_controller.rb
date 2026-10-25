class TradelinesController < ApplicationController
  require_permission :read_tradelines, only: %i[index show]
  require_permission :create_tradeline, only: :create

  def index
    @tradelines = paginate(Tradeline.order(:id))
  end

  def show
    @tradeline = Tradeline.find(params[:id])
  end

  def create
    @tradeline = Tradeline.new(tradeline_params)

    saved = Tradeline.transaction do
      @tradeline.save && AuditEvent.record!("tradeline.created", auditable: @tradeline, metadata: {
        name: @tradeline.name, amount: MoneyAttribute.format(@tradeline.amount)
      })
    end

    if saved
      render :show, status: :created, location: @tradeline
    else
      render_validation_errors(@tradeline)
    end
  end

  private

  def tradeline_params
    params.require(:tradeline).permit(:name, :amount)
  end
end
