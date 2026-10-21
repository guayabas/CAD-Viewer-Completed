require "test_helper"

class TessellatePartJobTest < ActiveJob::TestCase
  test "meshes the sample STEP file and marks the part ready" do
    skip "tessellator not built (cmake --build tessellator/build)" unless real_tessellator_available?
    part = build_part
    part.save!

    TessellatePartJob.perform_now(part)

    part.reload
    assert part.ready?, part.error_message
    assert_nil part.error_message
    tessellation = part.latest_tessellation
    assert_equal 117, tessellation.face_count
    assert_equal tessellation.face_count, tessellation.face_map["primitives"].sum { |p| p["faces"].size }
    assert_in_delta 0.8, tessellation.bbox["max"][0] - tessellation.bbox["min"][0], 0.001 # 800 mm long, in meters
    assert tessellation.glb.attached?
    assert_equal "model/gltf-binary", tessellation.glb.content_type
    assert_equal "glTF", tessellation.glb.download[0, 4]
  end

  test "marks the part failed with the tessellator's message" do
    part = build_part
    part.save!

    with_fake_tessellator('echo "tessellator: STEP transfer failed for $1" >&2; exit 1') do
      TessellatePartJob.perform_now(part)
    end

    part.reload
    assert part.failed?
    assert_equal "STEP transfer failed for nist.stp", part.error_message
    assert_empty part.tessellations
  end

  test "marks the part failed when the tessellator times out" do
    part = build_part
    part.save!

    with_fake_tessellator("sleep 10", timeout: 1) do
      TessellatePartJob.perform_now(part)
    end

    assert part.reload.failed?
    assert_equal "Tessellation timed out after 1 s", part.error_message
  end
end
