class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.references :app, null: false, foreign_key: true
      t.string :review_id, null: false
      t.string :author
      t.string :title
      t.text :content
      t.integer :rating
      t.string :version
      t.datetime :published_at
      t.timestamps
      
      t.index :review_id, unique: true
      t.index :rating
      t.index :published_at
    end
  end
end
