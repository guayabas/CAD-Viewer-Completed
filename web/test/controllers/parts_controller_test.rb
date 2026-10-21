require "test_helper"

class PartsControllerTest < ActionDispatch::IntegrationTest
  test "POST /parts saves the upload, queues the job and returns the pending part" do
    assert_difference -> { Part.count }, 1 do
      assert_enqueued_with(job: TessellatePartJob) do
        post parts_url, params: { file: sample_step_upload }
      end
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "nist_ctc_01_asme1_ap242-e1", body["name"]
    assert_equal "step", body["file_format"]
    assert_equal "pending", body["status"]
    assert_nil body["tessellation"]
    assert_equal part_url(body["id"]), response.headers["Location"]
  end

  test "POST /parts uses the given name" do
    post parts_url, params: { file: sample_step_upload, name: "Bracket A" }
    assert_equal "Bracket A", response.parsed_body["name"]
  end

  test "POST /parts rejects other file types" do
    file = Rack::Test::UploadedFile.new(StringIO.new(+"hello"), "text/plain", original_filename: "notes.txt")
    assert_no_difference -> { Part.count } do
      post parts_url, params: { file: file }
    end
    assert_response :unprocessable_entity
    assert_equal [ "File format must be STEP (.step or .stp)" ], response.parsed_body["errors"]
  end

  test "POST /parts without a file is a bad request" do
    post parts_url
    assert_response :bad_request
  end

  test "POST /parts refuses bodies over the size limit" do
    post parts_url, params: { file: sample_step_upload },
                    headers: { "CONTENT_LENGTH" => (Part::MAX_FILE_SIZE + 2.megabytes).to_s }
    assert_response :content_too_large
  end

  test "GET /parts lists parts without face maps" do
    get parts_url
    assert_response :success
    parts = response.parsed_body["parts"]
    assert_equal Part.count, parts.size
    bracket = parts.find { |p| p["name"] == "bracket" }
    assert_equal 12, bracket["tessellation"]["triangle_count"]
    assert_not bracket["tessellation"].key?("face_map")
  end

  test "GET /parts/:id includes the face map" do
    get part_url(parts(:bracket))
    assert_response :success
    tessellation = response.parsed_body["tessellation"]
    assert_equal 2, tessellation["face_map"]["primitives"].first["faces"].size
    assert_nil tessellation["glb_url"] # the fixture has no GLB attached
  end

  test "GET /parts/:id for a missing part is 404" do
    get part_url(id: 0)
    assert_response :not_found
    assert_equal "Not found", response.parsed_body["error"]
  end
end
