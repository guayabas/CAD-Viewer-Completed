require "test_helper"

class TessellationTest < ActiveSupport::TestCase
  test "fixture is valid" do
    assert tessellations(:bracket_default).valid?
  end

  test "requires positive deflections and counts" do
    tessellation = tessellations(:bracket_default)
    tessellation.linear_deflection = 0
    tessellation.triangle_count = -1
    assert_not tessellation.valid?
    assert tessellation.errors.key?(:linear_deflection)
    assert tessellation.errors.key?(:triangle_count)
  end

  test "requires bbox and face map" do
    tessellation = tessellations(:bracket_default)
    tessellation.bbox = nil
    tessellation.face_map = nil
    assert_not tessellation.valid?
    assert tessellation.errors.key?(:bbox)
    assert tessellation.errors.key?(:face_map)
  end

  test "attributes_from_metadata maps the tessellator JSON" do
    meta = {
      "occt_version" => "7.6.3",
      "settings" => { "rel_deflection" => 0.01, "linear_deflection_m" => 0.009, "angular_deflection_rad" => 0.1 },
      "bbox" => { "min" => [ 0, 0, 0 ], "max" => [ 1, 1, 1 ] },
      "triangle_count" => 12, "face_count" => 6,
      "timings_ms" => { "total" => 5.0 },
      "face_map" => { "primitives" => [] }
    }
    attributes = Tessellation.attributes_from_metadata(meta)
    assert_equal 0.009, attributes[:linear_deflection]
    assert_equal 6, attributes[:face_count]
    assert_equal({ "total" => 5.0 }, attributes[:timings])
  end
end
