class CreateParts < ActiveRecord::Migration[8.0]
  def change
    create_table :parts do |t|
      t.string  :name,        null: false
      t.string  :file_format, null: false
      t.integer :status,      null: false, default: 0
      t.text    :error_message
      t.timestamps
    end
    add_index :parts, :status
  end
end
