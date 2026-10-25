Rails.application.routes.draw do
  # Unauthenticated liveness probe (load balancers, bin/integration).
  get "up" => "rails/health#show", as: :rails_health_check

  # Interactive API docs (Swagger UI) and the OpenAPI document. Public, like
  # most API references; the API itself still requires an API key.
  unless ENV["API_DOCS_ENABLED"] == "false"
    mount Rswag::Ui::Engine => "/api-docs"
    mount Rswag::Api::Engine => "/api-docs"
    root to: redirect("/api-docs")
  end

  defaults format: :json do
    resources :tradelines, only: %i[index show create] do
      resources :deposits, only: %i[index show create]
    end

    resources :audit_events, only: :index
  end
end
