require "test_helper"

class ViewerControllerTest < ActionDispatch::IntegrationTest
  test "GET / serves the built viewer without caching" do
    created = !ViewerController::INDEX.exist? # write a stand-in index.html unless the real one is there
    if created
      FileUtils.mkdir_p(ViewerController::INDEX.dirname)
      File.write(ViewerController::INDEX, "<!doctype html><title>CAD Viewer</title>")
    end

    get root_url
    assert_response :success
    assert_equal "text/html", response.media_type
    assert_equal "no-cache", response.headers["Cache-Control"]
    assert_includes response.body, "CAD Viewer"
  ensure
    FileUtils.rm_rf(ViewerController::INDEX.dirname) if created
  end

  test "GET / explains how to run the viewer when it isn't built in" do
    skip "viewer is built into this checkout" if ViewerController::INDEX.exist?

    get root_url
    assert_response :not_found
    assert_includes response.body, "npm run dev"
  end
end
