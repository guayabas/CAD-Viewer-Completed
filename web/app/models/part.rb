# A CAD file someone uploaded. The meshes made from it live in tessellations.
class Part < ApplicationRecord
  # Formats the schema allows. Only STEP can be uploaded today (see EXTENSIONS).
  FORMATS = %w[step iges brep].freeze
  # Upload file extension -> file_format. Add ".igs"/".iges"/".brep" once the tessellator reads them.
  EXTENSIONS = { ".step" => "step", ".stp" => "step" }.freeze
  MAX_FILE_SIZE = 50.megabytes

  has_one_attached :source_file
  has_many :tessellations, dependent: :destroy
  # The newest mesh; the API and viewer show this one.
  has_one :latest_tessellation, -> { order(created_at: :desc, id: :desc) }, class_name: "Tessellation"

  # Stored as an integer; Rails adds pending?/processing!/... and Part.ready etc.
  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }, default: :pending

  validates :name, presence: true, length: { maximum: 255 }
  validates :file_format, inclusion: { in: FORMATS, message: "must be STEP (.step or .stp)" }
  validate :source_file_is_acceptable

  # "bracket.STP" -> "step"; nil if we don't accept that extension.
  def self.format_for(filename)
    EXTENSIONS[File.extname(filename.to_s).downcase]
  end

  private

  def source_file_is_acceptable
    if !source_file.attached?
      errors.add(:source_file, "is missing")
    elsif source_file.blob.byte_size > MAX_FILE_SIZE
      errors.add(:source_file, "is larger than #{MAX_FILE_SIZE / 1.megabyte} MB")
    end
  end
end
