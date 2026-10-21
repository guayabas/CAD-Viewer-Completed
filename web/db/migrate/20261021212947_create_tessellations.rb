# One row per meshing of a part. A part can have several (coarse/fine quality levels),
# which is why this is its own table instead of columns on parts.
class CreateTessellations < ActiveRecord::Migration[8.1]
  def change
    create_table :tessellations do |t|
      # t.references adds part_id, an index on it, and a foreign key to parts.
      t.references :part, null: false, foreign_key: true

      # Mesh quality. rel_deflection is the input (fraction of the bbox diagonal);
      # linear_deflection is the absolute value it produced, in meters.
      t.float :rel_deflection,     null: false
      t.float :linear_deflection,  null: false
      t.float :angular_deflection, null: false

      t.integer :triangle_count, null: false
      t.integer :face_count,     null: false

      # {"min": [x, y, z], "max": [x, y, z]} in meters, glTF axes (Y up).
      t.jsonb :bbox, null: false
      # B-rep face id -> triangle range per glTF primitive (see tessellator/tessellator.cpp).
      t.jsonb :face_map, null: false
      # {"read": ms, "mesh": ms, "export": ms, "total": ms}
      t.jsonb :timings, null: false, default: {}
      t.string :occt_version

      t.timestamps
    end
  end
end
