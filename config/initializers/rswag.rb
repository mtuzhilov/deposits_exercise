# Interactive API documentation at /api-docs (Swagger UI), backed by the
# OpenAPI document in swagger/v1/openapi.json (generated from spec/docs).
# Set API_DOCS_ENABLED=false to stop serving them (see config/routes.rb).

Rswag::Api.configure do |c|
  c.openapi_root = Rails.root.join("swagger").to_s

  # Point "Try it out" at whichever host is serving the docs, so it works on
  # any port or domain without regenerating the file.
  c.swagger_filter = lambda do |openapi, env|
    request = Rack::Request.new(env)
    openapi["servers"] = [{ "url" => request.base_url, "description" => "This server" }]
  end
end

Rswag::Ui.configure do |c|
  c.openapi_endpoint "/api-docs/v1/openapi.json", "Deposits API v1"

  # Passed straight to SwaggerUIBundle.
  c.config_object.merge!(
    persistAuthorization: true,   # keep the pasted API key across page reloads
    displayRequestDuration: true,
    docExpansion: "list",
    defaultModelsExpandDepth: 1,
    filter: true,                 # search box for operations
    tryItOutEnabled: false
  )
end
