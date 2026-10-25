source "https://rubygems.org"

ruby "~> 3.3.0"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1"

# Use sqlite3 as the database for Active Record
gem "sqlite3", "~> 1.4"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"


# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Pagination with metadata in response headers [https://github.com/ddnexus/pagy]
gem "pagy", "~> 9.0"

# One-line structured (JSON) request logs [https://github.com/roidrage/lograge]
gem "lograge"

# OpenAPI docs: served as JSON/YAML and browsable with Swagger UI at /api-docs [https://github.com/rswag/rswag]
gem "rswag-api", "~> 2.17"
gem "rswag-ui", "~> 2.17"

# Request throttling to protect the API and slow token brute-forcing [https://github.com/rack/rack-attack]
gem "rack-attack"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ]
  gem "rspec-rails"
  gem "pry"
  gem "factory_bot_rails"
  # Generates the OpenAPI document from request specs (rake rswag:specs:swaggerize)
  gem "rswag-specs", "~> 2.17"
end

group :test do
  gem "shoulda-matchers"
  gem "simplecov", require: false
end

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

