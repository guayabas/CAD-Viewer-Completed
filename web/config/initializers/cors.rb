# CORS: which browser origins may call this API. The viewer runs on another origin
# (Vite on localhost:5173 in dev, GitHub Pages in production), so the browser asks first.
#
# CORS_ORIGINS is a comma-separated list, e.g.
#   CORS_ORIGINS=https://<user>.github.io,http://localhost:5173
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "http://localhost:5173").split(",").map(&:strip))

    # The API, plus Active Storage URLs (the GLB download redirects through /rails/active_storage).
    resource "/parts*", headers: :any, methods: %i[get post options], expose: [ "Location" ]
    resource "/rails/active_storage/*", headers: :any, methods: %i[get head options]
  end
end
