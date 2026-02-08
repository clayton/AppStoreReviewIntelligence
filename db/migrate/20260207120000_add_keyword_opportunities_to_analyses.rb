class AddKeywordOpportunitiesToAnalyses < ActiveRecord::Migration[8.0]
  def change
    add_column :analyses, :keyword_opportunities, :json, default: {}
  end
end
