# Limits that keep the public demo inside free tiers (Backblaze B2: 10 GB storage). B2's Caps &
# Alerts are the hard stop; these keep the app well below them, with a clear message for users.
# Override with environment variables.
Rails.application.configure do
  # Total size of all stored files (uploaded STEP + generated GLB), checked before each upload.
  # Half of B2's free 10 GB, leaving room for the GLBs made after the check.
  config.x.uploads.storage_quota = Integer(ENV.fetch("STORAGE_QUOTA_MB", 5_000)).megabytes
  # Uploads accepted per day from all visitors together (per visitor: rate_limit in PartsController).
  config.x.uploads.daily_limit = Integer(ENV.fetch("DAILY_UPLOAD_LIMIT", 200))
end
