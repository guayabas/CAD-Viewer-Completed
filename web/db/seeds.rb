# Starting data: the NIST CTC 01 sample part, so a fresh database (local or on Render) has a
# meshed part to show. Runs with `bin/rails db:seed`, and automatically when `bin/rails db:prepare`
# creates a new database. Safe to run again: it skips the part if it already exists.
SAMPLE_STEP = Rails.root.join("../samples/nist_ctc_01_asme1_ap242-e1.stp")
SAMPLE_NAME = "NIST CTC 01"

if Part.exists?(name: SAMPLE_NAME)
  puts "Seed: #{SAMPLE_NAME} already exists"
elsif !SAMPLE_STEP.exist?
  puts "Seed: #{SAMPLE_STEP} not found, skipping"
else
  part = File.open(SAMPLE_STEP, "rb") do |io|
    Part.create!(name: SAMPLE_NAME, file_format: "step",
                 source_file: { io: io, filename: SAMPLE_STEP.basename.to_s, content_type: "application/step" })
  end
  # perform_now, not perform_later: this command exits right away, so a queued job could be lost.
  TessellatePartJob.perform_now(part)
  puts "Seed: #{SAMPLE_NAME} is #{part.reload.status}#{" (#{part.error_message})" if part.failed?}"
end
