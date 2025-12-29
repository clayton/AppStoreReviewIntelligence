class AddPersonasToAnalyses < ActiveRecord::Migration[8.0]
  def change
    add_column :analyses, :personas, :json, default: []
    add_column :analyses, :raw_persona_extractions, :json, default: []
  end
end
