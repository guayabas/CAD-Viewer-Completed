# Base class for the JSON API. ActionController::API is ActionController::Base without
# cookies, sessions, CSRF tokens or HTML layouts, which a cross-origin JSON client doesn't use.
class ApiController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end

  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: e.message }, status: :bad_request
  end
end
