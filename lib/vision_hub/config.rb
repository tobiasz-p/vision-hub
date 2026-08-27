# frozen_string_literal: true

require "json"

module VisionHub
  # Loads and validates cameras.json. A Configuration is always constructible:
  # when the file is missing, unreadable, or invalid the error text lands in
  # #error so the daemon can ship a config_error event instead of crashing.
  #
  # @!attribute [r] cameras
  #   @return [Array<Camera>] all parsed cameras (both enabled and disabled)
  # @!attribute [r] error
  #   @return [String, nil] error description if parsing or validation failed
  class Configuration
    # Maximum allowed configuration file size in bytes (256 KiB).
    # @return [Integer]
    MAX_BYTES = 256 * 1024

    # Maximum number of cameras permitted in the configuration array.
    # @return [Integer]
    MAX_CAMERAS = 32

    attr_reader :cameras, :error

    # Loads and validates configuration from the specified file path.
    #
    # @param path [String] path to cameras.json
    # @return [Configuration] parsed configuration instance
    def self.load(path)
      text = read_text(path)
      return text if text.is_a?(Configuration)

      parse(text)
    end

    # Reads file contents up to MAX_BYTES bytes, returning error Configuration on failure.
    #
    # @param path [String] file path to read
    # @return [String, Configuration] file contents or an error Configuration instance
    def self.read_text(path)
      stat = File.stat(path)
      return new([], error: "#{path}: file exceeds #{MAX_BYTES} bytes") if stat.size > MAX_BYTES

      text = File.open(path, "rb:UTF-8") { |f| f.read(MAX_BYTES + 1) }
      return new([], error: "#{path}: file exceeds #{MAX_BYTES} bytes") if text.nil? || text.bytesize > MAX_BYTES

      text
    rescue StandardError => e
      new([], error: "#{path}: #{e.class}: #{e.message}")
    end

    # Parses and validates raw JSON text containing camera definitions.
    #
    # @param text [String] JSON string
    # @return [Configuration] configuration object with parsed cameras or error text
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

    # Validates the root structure and length of the parsed JSON.
    #
    # @param raw [Object] parsed JSON root
    # @return [void]
    # @raise [ConfigError] if the root object is invalid or exceeds MAX_CAMERAS
    def self.validate_raw!(raw)
      unless raw.is_a?(Hash) && raw["cameras"].is_a?(Array)
        raise ConfigError, 'top level must be an object with a "cameras" array'
      end

      return unless raw["cameras"].size > MAX_CAMERAS

      raise ConfigError, "cameras array exceeds maximum limit of #{MAX_CAMERAS} cameras"
    end

    # Asserts that all camera IDs within the parsed list are unique.
    #
    # @param cameras [Array<Camera>] list of parsed cameras
    # @return [void]
    # @raise [ConfigError] if a duplicate camera ID is detected
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

    # Initializes a Configuration value object.
    #
    # @param cameras [Array<Camera>] list of parsed Camera objects
    # @param error [String, nil] optional error string if configuration failed to load
    def initialize(cameras, error: nil)
      @cameras = cameras.freeze
      @error = error
      freeze
    end

    # Checks whether the configuration is valid without errors.
    #
    # @return [Boolean] true if no errors were encountered
    def ok?
      error.nil?
    end

    # Returns the list of enabled cameras.
    #
    # @return [Array<Camera>] enabled cameras
    def active_cameras
      cameras.select(&:enabled?)
    end

    # Finds an active camera by its unique identifier.
    #
    # @param id [String] camera ID
    # @return [Camera, nil] matching camera or nil if not found
    def camera_by_id(id)
      active_cameras.find { |camera| camera.id == id }
    end
  end
end
