require "test_helper"

# The Ruby wrapper around the C++ CLI. Fake shell-script binaries cover the failure cases
# quickly; the real binary is used when it has been built.
class TessellatorTest < ActiveSupport::TestCase
  test "turns a CLI error into a message with the user's file name" do
    with_fake_tessellator('echo "tessellator: could not read STEP file $1" >&2; exit 1') do
      Dir.mktmpdir do |dir|
        error = assert_raises(Tessellator::Error) do
          Tessellator.new.run("/tmp/ActiveStorage-123.step", dir, display_name: "bracket.stp")
        end
        assert_equal "Could not read STEP file bracket.stp", error.message
      end
    end
  end

  test "falls back to a message per exit code when stderr is empty" do
    with_fake_tessellator("exit 3") do
      Dir.mktmpdir do |dir|
        error = assert_raises(Tessellator::Error) { Tessellator.new.run("in.step", dir) }
        assert_equal "Could not mesh or export the model", error.message
      end
    end
  end

  test "stops a tessellator that runs too long" do
    with_fake_tessellator("sleep 10", timeout: 1) do
      Dir.mktmpdir do |dir|
        error = assert_raises(Tessellator::Error) { Tessellator.new.run("in.step", dir) }
        assert_equal "Tessellation timed out after 1 s", error.message
      end
    end
  end

  test "reports a missing binary" do
    with_tessellator_config(bin: "/nonexistent/tessellator") do
      error = assert_raises(Tessellator::Error) { Tessellator.new.run("in.step", Dir.tmpdir) }
      assert_match "Tessellator not found", error.message
    end
  end

  test "meshes the sample STEP file with the real binary" do
    skip "tessellator not built (cmake --build tessellator/build)" unless real_tessellator_available?

    Dir.mktmpdir do |dir|
      result = Tessellator.new.run(SAMPLE_STEP, dir)
      assert_equal "glTF", File.binread(result.glb_path, 4)
      assert_equal 117, result.metadata["face_count"]
      assert_operator result.metadata["triangle_count"], :>, 0
    end
  end
end
