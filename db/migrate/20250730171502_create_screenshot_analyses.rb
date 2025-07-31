class CreateScreenshotAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :screenshot_analyses do |t|
      t.references :app, null: false, foreign_key: true
      t.integer :screenshot_count
      t.text :analysis
      t.json :screenshot_urls
      t.timestamps
    end
    
    add_index :screenshot_analyses, :created_at
  end
end
