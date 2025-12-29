class AddInsiderLanguageToAnalyses < ActiveRecord::Migration[8.0]
  def change
    add_column :analyses, :insider_language, :json, default: {}
  end
end
