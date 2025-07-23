class CreateAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :analyses do |t|
      t.string :keyword, null: false
      t.text :llm_analysis
      t.text :patterns
      t.text :opportunities
      t.integer :total_reviews_analyzed
      t.string :llm_model
      t.timestamps
      
      t.index :keyword
      t.index :created_at
    end
  end
end
