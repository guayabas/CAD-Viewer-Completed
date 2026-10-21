# Settings for the C++ tessellator CLI (../tessellator). Read once at boot; available as
# Rails.configuration.x.tessellator.*. Override with environment variables in production.
Rails.application.configure do
  config.x.tessellator.bin = ENV.fetch("TESSELLATOR_BIN") { Rails.root.join("../tessellator/build/tessellator").to_s }
  # Seconds before the tessellator is killed; protects the worker from huge or pathological files.
  config.x.tessellator.timeout = Integer(ENV.fetch("TESSELLATOR_TIMEOUT", 120))
  config.x.tessellator.rel_deflection = Float(ENV.fetch("TESSELLATOR_REL_DEFLECTION", 0.01))
  config.x.tessellator.angular_deflection = Float(ENV.fetch("TESSELLATOR_ANGULAR_DEFLECTION", 0.1))
end
