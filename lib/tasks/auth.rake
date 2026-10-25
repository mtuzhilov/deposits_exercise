namespace :auth do
  desc "Issue an API key: bin/rails \"auth:create_key[name,role]\" (role: viewer|operator|admin). Optional EXPIRES_IN_DAYS=n"
  task :create_key, %i[name role] => :environment do |_t, args|
    abort "Usage: bin/rails \"auth:create_key[name,role]\" (role: #{ApiKey::ROLES.join('|')})" if args[:name].blank?

    expires_at = ENV["EXPIRES_IN_DAYS"].presence&.then { |days| Integer(days).days.from_now }
    key, token = ApiKey.issue!(name: args[:name], role: args[:role] || "viewer", expires_at: expires_at)

    puts "Created #{key.role} key '#{key.name}' (prefix #{key.token_prefix}, " \
         "expires #{key.expires_at&.iso8601 || 'never'})."
    puts "Token (shown once, store it securely):"
    puts token
  rescue ActiveRecord::RecordInvalid => e
    abort e.message
  end

  desc "List API keys (never shows tokens)"
  task list_keys: :environment do
    puts format("%-5s %-14s %-9s %-8s %-25s %s", "ID", "PREFIX", "ROLE", "STATUS", "LAST USED", "NAME")
    ApiKey.order(:id).each do |key|
      puts format("%-5s %-14s %-9s %-8s %-25s %s", key.id, key.token_prefix, key.role, key.status,
                  key.last_used_at&.iso8601 || "never", key.name)
    end
  end

  desc "Revoke an API key by its prefix: bin/rails \"auth:revoke_key[dpx_xxxxxxxx]\""
  task :revoke_key, %i[prefix] => :environment do |_t, args|
    key = ApiKey.find_by(token_prefix: args[:prefix].to_s)
    abort "No API key with prefix #{args[:prefix].inspect}" unless key

    key.revoke!
    puts "Revoked key '#{key.name}' (#{key.token_prefix})."
  end
end
