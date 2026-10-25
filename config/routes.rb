Rails.application.routes.draw do
  # Unauthenticated liveness probe (load balancers, bin/integration).
  get "up" => "rails/health#show", as: :rails_health_check

  defaults format: :json do
    resources :tradelines, only: %i[index show create] do
      resources :deposits, only: %i[index show create]
    end

    resources :audit_events, only: :index
  end
end
