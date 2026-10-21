ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # The small NIST STEP file committed in samples/ (see samples/README.md).
    SAMPLE_STEP = Rails.root.join("../samples/nist_ctc_01_asme1_ap242-e1.stp").to_s

    def sample_step_upload
      Rack::Test::UploadedFile.new(SAMPLE_STEP, "application/step")
    end

    # A new unsaved part with the sample STEP attached.
    def build_part(**attributes)
      part = Part.new(name: "nist", file_format: "step", **attributes)
      part.source_file.attach(io: File.open(SAMPLE_STEP, "rb"), filename: "nist.stp") unless attributes.key?(:source_file)
      part
    end

    # Runs the block with Rails.configuration.x.tessellator settings changed, then restores them.
    def with_tessellator_config(**settings)
      config = Rails.configuration.x.tessellator
      previous = settings.keys.index_with { |key| config.public_send(key) }
      settings.each { |key, value| config.public_send("#{key}=", value) }
      yield
    ensure
      previous&.each { |key, value| config.public_send("#{key}=", value) }
    end

    # Runs the block with TESSELLATOR_BIN pointing at a throwaway shell script.
    def with_fake_tessellator(script, **settings, &block)
      Dir.mktmpdir do |dir|
        bin = File.join(dir, "fake_tessellator")
        File.write(bin, "#!/bin/sh\n#{script}\n")
        File.chmod(0o755, bin)
        with_tessellator_config(bin: bin, **settings, &block)
      end
    end

    def real_tessellator_available?
      File.executable?(Rails.configuration.x.tessellator.bin)
    end
  end
end
