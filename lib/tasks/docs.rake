namespace :docs do
  desc "Regenerate swagger/v1/openapi.json from the request specs in spec/docs"
  task :generate do
    # rswag's own rswag:specs:swaggerize task globs spec/integration too, which
    # holds the live HTTP suite, so run the doc specs directly.
    # Run in a clean environment: the rails command process exports RAILS_ENV
    # and Bundler/RUBYOPT settings that make the child rspec misbehave.
    Bundler.with_unbundled_env do
      sh({ "RAILS_ENV" => "test" },
         "bundle exec rspec spec/docs --format Rswag::Specs::SwaggerFormatter --dry-run --order defined")
    end
  end
end
