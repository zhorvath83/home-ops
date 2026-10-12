# Sure kategorizált tranzakcióinak exportja a valós adatos bake-offhoz — csak olvas, semmit nem ír.
# A sure-server podban fut:
#   kubectl exec -i -n selfhosted deploy/sure-server -c app -- bin/rails runner - < tools/llm-bakeoff/sure_export.rb
# Egyetlen JSON sort ír ki (EXPORT: előtaggal): a kategóriák listája és a kategorizált tranzakciók.
require "json"

family = Family.first
transactions = Transaction.where.not(category_id: nil).includes(:category, :merchant, :entry)
payload = {
  categories: family.categories.order(:name).pluck(:name),
  transactions: transactions.map do |t|
    { name: t.entry.name, amount: t.entry.amount.to_s, currency: t.entry.currency,
      merchant: t.merchant&.name, category: t.category.name }
  end
}
puts "EXPORT:" + payload.to_json
