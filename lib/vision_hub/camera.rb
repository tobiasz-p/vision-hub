# frozen_string_literal: true

module VisionHub
  # Raised for any problem found while parsing or validating cameras.json.
  # The message is user-facing: it is shipped verbatim to the UI.
  class ConfigError < StandardError; end

  # Immutable description of one camera from cameras.json. Carries no secret:
  # passwords are supplied as arguments when URLs are built, and never stored
  # on the camera object.
  #
  # @!attribute [r] index
  #   @return [Integer] zero-based index of the camera in configuration
  # @!attribute [r] id
  #   @return [String] unique identifier of the camera
  # @!attribute [r] name
  #   @return [String] display name of the camera
  # @!attribute [r] host
  #   @return [String] hostname or IP address
  # @!attribute [r] port
  #   @return [Integer] RTSP port number
  # @!attribute [r] username
  #   @return [String, nil] authentication username, or nil if anonymous
  # @!attribute [r] main_path
  #   @return [String] mainstream RTSP URL path
  # @!attribute [r] sub_path
  #   @return [String] substream RTSP URL path
  # @!attribute [r] enabled
  #   @return [Boolean] whether the camera is enabled in configuration
  class Camera
    # Default RTSP port number.
    # @return [Integer]
    DEFAULT_PORT = 554

    # Default mainstream stream path.
    # @return [String]
    DEFAULT_MAIN_PATH = "/stream1"

    # Default substream stream path.
    # @return [String]
    DEFAULT_SUB_PATH = "/stream2"

    # Regex pattern matching valid camera identifiers.
    # @return [Regexp]
    ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

    # Maximum permitted character length for a camera ID.
    # @return [Integer]
    MAX_ID_LENGTH = 64

    # Maximum permitted character length for a camera name.
    # @return [Integer]
    MAX_NAME_LENGTH = 128

    # Maximum permitted character length for a camera host.
    # @return [Integer]
    MAX_HOST_LENGTH = 255

    # Maximum permitted character length for a username.
    # @return [Integer]
    MAX_USERNAME_LENGTH = 128

    # Maximum permitted character length for stream paths.
    # @return [Integer]
    MAX_PATH_LENGTH = 512

    attr_reader :index, :id, :name, :host, :port, :username, :main_path, :sub_path, :enabled

    # Constructs and validates a Camera instance from a raw JSON configuration hash.
    #
    # @param raw [Hash] parsed JSON entry from cameras.json
    # @param index [Integer] zero-based index in the configuration array
    # @return [Camera] validated, frozen camera instance
    # @raise [ConfigError] if validation fails
    def self.from_hash(raw, index)
      where = "cameras[#{index}]"

      raise ConfigError, "#{where}: expected an object" unless raw.is_a?(Hash)

      id = require_string(raw, "id", where, max_length: MAX_ID_LENGTH)
      unless id.match?(ID_PATTERN)
        raise ConfigError, "#{where}.id: #{id.inspect} may only contain letters, digits, dots, dashes, underscores"
      end

      new(
        index:,
        id:,
        name: optional_string(raw, "name", where, max_length: MAX_NAME_LENGTH) || id,
        host: require_string(raw, "host", where, max_length: MAX_HOST_LENGTH),
        port: parse_port(raw, where),
        username: optional_string(raw, "username", where, max_length: MAX_USERNAME_LENGTH),
        main_path: parse_path(raw, "mainPath", DEFAULT_MAIN_PATH, where),
        sub_path: parse_path(raw, "subPath", DEFAULT_SUB_PATH, where),
        enabled: raw.key?("enabled") ? raw.fetch("enabled") != false : true
      )
    end

    # Validates and extracts a required non-empty string attribute.
    #
    # @param raw [Hash] raw configuration hash
    # @param key [String] key to look up
    # @param where [String] context description for error messages
    # @param max_length [Integer, nil] optional maximum string length
    # @return [String] extracted string value
    # @raise [ConfigError] if key is missing, empty, not a string, or exceeds max length
    def self.require_string(raw, key, where, max_length: nil)
      value = raw[key]
      raise ConfigError, "#{where}.#{key} is required" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      raise ConfigError, "#{where}.#{key} must be a string" unless value.is_a?(String)
      if max_length && value.length > max_length
        raise ConfigError, "#{where}.#{key} exceeds maximum length of #{max_length}"
      end

      value
    end

    # Validates and extracts an optional string attribute.
    #
    # @param raw [Hash] raw configuration hash
    # @param key [String] key to look up
    # @param where [String] context description for error messages
    # @param max_length [Integer, nil] optional maximum string length
    # @return [String, nil] extracted string value or nil if absent/empty
    # @raise [ConfigError] if value is present but not a string or exceeds max length
    def self.optional_string(raw, key, where, max_length: nil)
      value = raw[key]
      return nil if value.nil?
      raise ConfigError, "#{where}.#{key} must be a string" unless value.is_a?(String)
      if max_length && value.length > max_length
        raise ConfigError, "#{where}.#{key} exceeds maximum length of #{max_length}"
      end

      value.empty? ? nil : value
    end

    # Validates and extracts a TCP port number with default fallback.
    #
    # @param raw [Hash] raw configuration hash
    # @param where [String] context description for error messages
    # @return [Integer] parsed port number
    # @raise [ConfigError] if port is not an integer in 1..65535
    def self.parse_port(raw, where)
      value = raw.fetch("port", DEFAULT_PORT)
      unless value.is_a?(Integer) && value.between?(1, 65_535)
        raise ConfigError, "#{where}.port must be an integer between 1 and 65535"
      end

      value
    end

    # Validates and extracts a URL stream path starting with '/'.
    #
    # @param raw [Hash] raw configuration hash
    # @param key [String] key to look up
    # @param fallback [String] default path if key is missing
    # @param where [String] context description for error messages
    # @return [String] validated path
    # @raise [ConfigError] if path is not a string starting with '/' or exceeds max length
    def self.parse_path(raw, key, fallback, where)
      value = raw.fetch(key, fallback)
      unless value.is_a?(String) && value.start_with?("/")
        raise ConfigError, "#{where}.#{key} must be a string beginning with /"
      end
      if value.length > MAX_PATH_LENGTH
        raise ConfigError, "#{where}.#{key} exceeds maximum length of #{MAX_PATH_LENGTH}"
      end

      value
    end

    # Initializes a new immutable Camera value object.
    #
    # @param index [Integer] zero-based index in the configuration array
    # @param id [String] unique camera identifier
    # @param name [String] human-readable camera display name
    # @param host [String] camera hostname or IP
    # @param port [Integer] RTSP port number
    # @param username [String, nil] optional auth username
    # @param main_path [String] mainstream RTSP URL path
    # @param sub_path [String] substream RTSP URL path
    # @param enabled [Boolean] whether the camera is enabled
    def initialize(index:, id:, name:, host:, port:, username:, main_path:, sub_path:, enabled:)
      @index = index
      @id = id
      @name = name
      @host = host
      @port = port
      @username = username
      @main_path = main_path
      @sub_path = sub_path
      @enabled = enabled
      freeze
    end

    # Checks whether this camera is enabled.
    #
    # @return [Boolean]
    def enabled?
      enabled
    end

    # Checks whether this camera requires password authentication.
    #
    # @return [Boolean] true if a username is configured
    def wants_password?
      !username.nil?
    end

    # RTSP URL for the given stream path. +password+ may be nil for anonymous
    # cameras. Credentials are percent-encoded; they exist only inside the
    # returned string and are never logged or persisted by this class.
    #
    # @param path [String] RTSP path
    # @param password [String, nil] optional cleartext password
    # @return [String] full RTSP URL
    def url_for(path, password = nil)
      authority = "#{host}:#{port}"
      if username
        authority = "#{self.class.percent_encode(username)}:#{self.class.percent_encode(password.to_s)}@#{authority}"
      end
      "rtsp://#{authority}#{path}"
    end

    # Returns the full RTSP URL for the camera's high-resolution mainstream.
    #
    # @param password [String, nil] optional cleartext password
    # @return [String] full RTSP URL
    def mainstream_url(password = nil)
      url_for(main_path, password)
    end

    # Returns the full RTSP URL for the camera's low-resolution substream.
    #
    # @param password [String, nil] optional cleartext password
    # @return [String] full RTSP URL
    def substream_url(password = nil)
      url_for(sub_path, password)
    end

    # Percent-encode everything outside RFC 3986's unreserved set so usernames
    # and passwords containing :, @, /, %, spaces, or UTF-8 stay intact.
    #
    # @param value [String] string to percent-encode
    # @return [String] encoded string
    def self.percent_encode(value)
      value.b.gsub(/[^A-Za-z0-9._~-]/n) { |byte| format("%%%02X", byte.ord) }
    end
  end
end
