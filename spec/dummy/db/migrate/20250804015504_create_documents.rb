# frozen_string_literal: true

class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.string :title
      t.text :content

      t.timestamps
    end
  end
end
