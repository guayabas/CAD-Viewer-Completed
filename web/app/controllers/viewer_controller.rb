# Serves the connected viewer (the built React app) at "/", so the deployed app is one URL:
# the viewer and the API it calls share an origin, so the browser needs no CORS for it.
#
# The Docker image builds viewer/ with VITE_API_URL=/ and puts index.html in web/viewer/ and
# the hashed JS/CSS in public/viewer-assets/ (served by Rails with a long cache). index.html
# goes through this controller instead, with no-cache, so a deploy shows up on the next reload.
class ViewerController < ActionController::API
  INDEX = Rails.root.join("viewer", "index.html")

  def index
    if INDEX.exist?
      response.headers["Cache-Control"] = "no-cache"
      send_file INDEX, type: "text/html", disposition: "inline"
    else
      render plain: "The viewer isn't built into this server. In development, run it with Vite:\n" \
                    "  cd viewer && VITE_API_URL=http://localhost:3000 npm run dev\n", status: :not_found
    end
  end
end
