# One part as JSON. Used by index (list) and show (single part, with the face map).
json.extract! part, :id, :name, :file_format, :status, :error_message, :created_at, :updated_at

tessellation = part.latest_tessellation
if tessellation
  json.tessellation do
    json.extract! tessellation, :id, :rel_deflection, :linear_deflection, :angular_deflection,
                  :triangle_count, :face_count, :bbox, :timings, :occt_version, :created_at
    # Rails URL that redirects to the file (local disk in dev, a signed B2 URL in production).
    json.glb_url tessellation.glb.attached? ? rails_blob_url(tessellation.glb) : nil
    json.face_map tessellation.face_map if include_face_map
  end
else
  json.tessellation nil
end
