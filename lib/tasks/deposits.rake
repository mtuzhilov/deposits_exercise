namespace :deposits do
  desc "Check every tradeline's cached deposits_total against its deposits. FIX=1 to repair drift"
  task reconcile: :environment do
    drifted = 0
    Tradeline.find_each do |tradeline|
      drift = tradeline.deposits_total_drift
      next if drift.zero?

      drifted += 1
      puts "Tradeline #{tradeline.id}: cached #{MoneyAttribute.format(tradeline.deposits_total)}, drift #{MoneyAttribute.format(drift)}"
      tradeline.recalculate_deposits_total! if ENV["FIX"] == "1"
    end
    puts drifted.zero? ? "All tradelines reconcile." : "#{drifted} tradeline(s) drifted#{' (repaired)' if ENV['FIX'] == '1'}."
    exit 1 if drifted.positive? && ENV["FIX"] != "1"
  end
end
