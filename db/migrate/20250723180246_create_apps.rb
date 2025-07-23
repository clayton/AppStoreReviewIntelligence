class CreateApps < ActiveRecord::Migration[8.0]
  def change
    create_table :apps do |t|
      t.string :app_id, null: false
      t.string :name, null: false
      t.string :developer
      t.string :bundle_id
      t.decimal :price
      t.string :currency
      t.float :average_rating
      t.integer :rating_count
      t.string :version
      t.text :description
      t.string :icon_url
      t.string :keyword
      t.integer :search_rank
      t.timestamps
      
      t.index :app_id
      t.index :keyword
      t.index [:app_id, :keyword], unique: true
    end
  end
end
