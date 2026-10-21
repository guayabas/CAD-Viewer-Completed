require "test_helper"

class PartTest < ActiveSupport::TestCase
  test "valid with a name, a STEP format and a source file" do
    assert build_part.valid?
  end

  test "starts as pending" do
    assert build_part.pending?
  end

  test "requires a name" do
    part = build_part(name: "")
    assert_not part.valid?
    assert_includes part.errors[:name], "can't be blank"
  end

  test "requires a source file" do
    part = Part.new(name: "nist", file_format: "step")
    assert_not part.valid?
    assert_includes part.errors[:source_file], "is missing"
  end

  test "rejects formats outside the list" do
    part = build_part(file_format: "dwg")
    assert_not part.valid?
    assert_includes part.errors[:file_format], "must be STEP (.step or .stp)"
  end

  test "rejects files over the size limit" do
    part = build_part
    part.source_file.blob.byte_size = Part::MAX_FILE_SIZE + 1
    assert_not part.valid?
    assert_includes part.errors[:source_file], "is larger than 50 MB"
  end

  test "format_for maps STEP extensions, case-insensitively" do
    assert_equal "step", Part.format_for("bracket.step")
    assert_equal "step", Part.format_for("BRACKET.STP")
    assert_nil Part.format_for("notes.txt")
    assert_nil Part.format_for("bracket")
  end

  test "latest_tessellation is the newest one" do
    part = parts(:bracket)
    newer = part.tessellations.create!(tessellations(:bracket_default).attributes.except("id", "part_id", "created_at", "updated_at"))
    assert_equal newer, part.reload.latest_tessellation
  end

  test "destroying a part destroys its tessellations" do
    assert_difference -> { Tessellation.count }, -1 do
      parts(:bracket).destroy
    end
  end
end
