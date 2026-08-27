# frozen_string_literal: true

require "json"

module VisionHub
  # Loads and validates cameras.json. A Configuration is always constructible:
  # when the file is missing, unreadable, or invalid the error text lands in
  # #error so the daemon can ship a config_error event instead of crashing.
  class Configuration
    MAX_BYTES = 256 * 1024
    MAX_CAMERAS = 32

    attr_reader :cameras, :error

    def self.load(path)
      text = read_text(path)
      return text if text.is_a?(Configuration)

      parse(text)
    end

    def self.read_text(path)
      stat = File.stat(path)
      return new([], error: "#{path}: file exceeds #{MAX_BYTES} bytes") if stat.size > MAX_BYTES

      text = File.open(path, "rb:UTF-8") { |f| f.read(MAX_BYTES + 1) }
      return new([], error: "#{path}: file exceeds #{MAX_BYTES} bytes") if text.nil? || text.bytesize > MAX_BYTES

      text
    rescue StandardError => e
      new([], error: "#{path}: #{e.class}: #{e.message}")
    end

    def self.parse(text)
      cameras = []
      begin
        raw = JSON.parse(text)
        validate_raw!(raw)

        cameras = raw["cameras"].each_with_index.map { |entry, index| Camera.from_hash(entry, index) }
        assert_unique_ids(cameras)
      rescue ConfigError => e
        return new(cameras, error: e.message)
      rescue JSON::ParserError => e
        return new([], error: "invalid JSON: #{e.message}")
      end

      new(cameras)
    end

    def self.validate_raw!(raw)
      unless raw.is_a?(Hash) && raw["cameras"].is_a?(Array)
        raise ConfigError, 'top level must be an object with a "cameras" array'
      end

      return unless raw["cameras"].size > MAX_CAMERAS

      raise ConfigError, "cameras array exceeds maximum limit of #{MAX_CAMERAS} cameras"
    end

    def self.assert_unique_ids(cameras)
      seen = {}
      cameras.each do |camera|
        if seen.key?(camera.id)
          raise ConfigError,
                "cameras[#{camera.index}]: duplicate id #{camera.id.inspect} (also at index #{seen[camera.id]})"
        end
        seen[camera.id] = camera.index
      end
    end

    # +cameras+ holds every parsed entry (including 'enabled': false ones, so
    # the UI can list them greyed out); only enabled cameras are ever worked
    # with through #active_cameras.
    def initialize(cameras, error: nil)
      @cameras = cameras.freeze
      @error = error
      freeze
    end

    def ok?
      error.nil?
    end

    def active_cameras
      cameras.select(&:enabled?)
    end

    def camera_by_id(id)
      active_cameras.find { |camera| camera.id == id }
    end
  end
end
