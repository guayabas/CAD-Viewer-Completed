# GET /parts, GET /parts/:id, POST /parts (multipart field "file", optional "name").
# The JSON comes from app/views/parts/*.json.jbuilder.
class PartsController < ApiController
  # Public uploads: at most 10 per minute per IP (Rails 8 built-in, counts in Rails.cache).
  rate_limit to: 10, within: 1.minute, only: :create,
             with: -> { render json: { error: "Too many uploads. Try again in a minute." }, status: :too_many_requests }

  # Refuse oversized bodies from the Content-Length header before parsing the multipart form.
  before_action :reject_oversized_upload, only: :create

  def index
    @parts = Part.order(created_at: :desc).limit(100)
                 .includes(latest_tessellation: { glb_attachment: :blob })
  end

  def show
    @part = Part.find(params[:id])
  end

  def create
    file = params.require(:file)
    @part = Part.new(
      name: params[:name].presence || File.basename(file.original_filename.to_s, ".*"),
      file_format: Part.format_for(file.original_filename),
      source_file: file
    )

    if @part.save
      TessellatePartJob.perform_later(@part)
      render :show, status: :created, location: @part
    else
      render json: { errors: @part.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def reject_oversized_upload
    # Some headroom over the file limit for the rest of the multipart body.
    return unless request.content_length.to_i > Part::MAX_FILE_SIZE + 1.megabyte

    render json: { errors: [ "File is larger than #{Part::MAX_FILE_SIZE / 1.megabyte} MB" ] },
           status: :content_too_large
  end
end
