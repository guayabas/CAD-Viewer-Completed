# Meshes an uploaded part in the background (Solid Queue in production).
# pending -> processing -> ready, or failed with error_message.
class TessellatePartJob < ApplicationJob
  queue_as :default

  # Retrying won't fix a bad STEP file, so failures are final: the part is marked failed.
  def perform(part)
    part.update!(status: :processing, error_message: nil)

    Dir.mktmpdir("tessellate") do |dir|
      # source_file.open downloads the file (from disk or B2) to a temp file for the block.
      part.source_file.open do |source|
        result = Tessellator.new.run(source.path, dir, display_name: part.source_file.filename.to_s)
        save_tessellation(part, result)
      end
    end

    part.update!(status: :ready)
  rescue Tessellator::Error => e
    part.update!(status: :failed, error_message: e.message.truncate(2000))
  rescue => e
    # Unexpected (a bug, storage down...): still mark the part, then re-raise so it is logged.
    part.update!(status: :failed, error_message: "Internal error while processing the file")
    raise e
  end

  private

  def save_tessellation(part, result)
    tessellation = part.tessellations.new(Tessellation.attributes_from_metadata(result.metadata))
    File.open(result.glb_path, "rb") do |io|
      tessellation.glb.attach(io: io, filename: "#{part.name.parameterize.presence || "part"}.glb",
                              content_type: "model/gltf-binary")
      tessellation.save! # uploads the GLB, so it must happen while io is open
    end
  end
end
