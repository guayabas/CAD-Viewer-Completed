require "open3"

# Runs the C++ tessellator CLI: STEP in, GLB + JSON metadata out.
# A plain Ruby class (no table); it lives in app/models so Rails autoloads it.
class Tessellator
  class Error < StandardError; end

  Result = Data.define(:glb_path, :metadata)

  # Exit codes from tessellator.cpp, turned into messages users can read.
  EXIT_MESSAGES = {
    1 => "Could not read the STEP file",
    2 => "Tessellator usage error (a bug in the job)",
    3 => "Could not mesh or export the model"
  }.freeze
  TIMEOUT_EXIT = 124 # what coreutils `timeout` returns when it had to stop the command

  def initialize(config = Rails.configuration.x.tessellator)
    @bin = config.bin
    @timeout = config.timeout
    @rel_deflection = config.rel_deflection
    @angular_deflection = config.angular_deflection
  end

  # Writes out.glb and out.json into out_dir and returns a Result. Raises Tessellator::Error.
  # display_name replaces the temp input path in error messages (users know their file name).
  def run(input_path, out_dir, display_name: File.basename(input_path))
    raise Error, "Tessellator not found at #{@bin} (set TESSELLATOR_BIN)" unless File.executable?(@bin)

    glb_path = File.join(out_dir, "out.glb")
    meta_path = File.join(out_dir, "out.json")
    # `timeout` (coreutils) stops the process after @timeout seconds, and kills it 5 s later if
    # it ignores that. Simpler and safer than threads + Process.kill in Ruby.
    command = [ "timeout", "--kill-after=5", @timeout.to_s, @bin, input_path, glb_path,
                "--rel-deflection", @rel_deflection.to_s, "--angular", @angular_deflection.to_s,
                "--meta", meta_path ]
    _stdout, stderr, status = Open3.capture3(*command)

    unless status.success?
      raise Error, "Tessellation timed out after #{@timeout} s" if status.exitstatus == TIMEOUT_EXIT

      # The CLI prints one clear line per error ("tessellator: could not read STEP file <path>").
      details = stderr.lines.last(5).join.strip.gsub(input_path, display_name).gsub("tessellator: ", "")
      raise Error, details.presence&.upcase_first ||
                   EXIT_MESSAGES.fetch(status.exitstatus, "Tessellator failed (exit #{status.exitstatus.inspect})")
    end

    Result.new(glb_path: glb_path, metadata: JSON.parse(File.read(meta_path)))
  rescue JSON::ParserError, Errno::ENOENT => e
    raise Error, "Tessellator output could not be read: #{e.message}"
  end
end
