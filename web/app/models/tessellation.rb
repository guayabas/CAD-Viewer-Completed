# One meshing of a part: the GLB plus the metadata the tessellator wrote next to it.
class Tessellation < ApplicationRecord
  belongs_to :part
  has_one_attached :glb

  validates :rel_deflection, :linear_deflection, :angular_deflection, numericality: { greater_than: 0 }
  validates :triangle_count, :face_count, numericality: { only_integer: true, greater_than: 0 }
  validates :bbox, :face_map, presence: true

  # Attributes from the tessellator's --meta JSON (already parsed into a Hash).
  def self.attributes_from_metadata(meta)
    settings = meta.fetch("settings")
    {
      rel_deflection: settings.fetch("rel_deflection"),
      linear_deflection: settings.fetch("linear_deflection_m"),
      angular_deflection: settings.fetch("angular_deflection_rad"),
      triangle_count: meta.fetch("triangle_count"),
      face_count: meta.fetch("face_count"),
      bbox: meta.fetch("bbox"),
      face_map: meta.fetch("face_map"),
      timings: meta.fetch("timings_ms", {}),
      occt_version: meta["occt_version"]
    }
  end
end
