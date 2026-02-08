class CreateAsoAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :aso_analyses do |t|
      t.references :app, null: false, foreign_key: true
      t.string :keyword, null: false
      t.integer :competitor_count, null: false
      t.json :competitor_app_ids
      t.text :llm_analysis
      t.json :recommendations
      t.string :llm_model
      t.timestamps
    end

    add_index :aso_analyses, [:app_id, :keyword]
    add_index :aso_analyses, :created_at
    add_index :aso_analyses, :keyword
  end
end
