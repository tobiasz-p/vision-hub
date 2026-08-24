# frozen_string_literal: true

module VisionHub
  # Raised for any problem found while parsing or validating cameras.json.
  # The message is user-facing: it is shipped verbatim to the UI.
  class ConfigError < StandardError; end

  # Immutable description of one camera from cameras.json. Carries no secret:
  # passwords are supplied as arguments when URLs are built, and never stored
  # on the camera object.
  class Camera
    DEFAULT_PORT = 554
    DEFAULT_MAIN_PATH = "/stream1"
    DEFAULT_SUB_PATH = "/stream2"
    ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

    attr_reader :index, :id, :name, :host, :port, :username, :main_path, :sub_path, :enabled

    def self.from_hash(raw, index)
      where = "cameras[#{index}]"

      raise ConfigError, "#{where}: expected an object" unless raw.is_a?(Hash)

      id = require_string(raw, "id", where)
      unless id.match?(ID_PATTERN)
        raise ConfigError, "#{where}.id: #{id.inspect} may only contain letters, digits, dots, dashes, underscores"
      end

      new(
        index:,
        id:,
        name: optional_string(raw, "name", where) || id,
        host: require_string(raw, "host", where),
        port: parse_port(raw, where),
        username: optional_string(raw, "username", where),
        main_path: parse_path(raw, "mainPath", DEFAULT_MAIN_PATH, where),
        sub_path: parse_path(raw, "subPath", DEFAULT_SUB_PATH, where),
        enabled: raw.key?("enabled") ? raw.fetch("enabled") != false : true
      )
    end

    def self.require_string(raw, key, where)
      value = raw[key]
      raise ConfigError, "#{where}.#{key} is required" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      raise ConfigError, "#{where}.#{key} must be a string" unless value.is_a?(String)

      value
    end

    def self.optional_string(raw, key, where)
      value = raw[key]
      return nil if value.nil?
      raise ConfigError, "#{where}.#{key} must be a string" unless value.is_a?(String)

      value.empty? ? nil : value
    end

    def self.parse_port(raw, where)
      value = raw.fetch("port", DEFAULT_PORT)
      unless value.is_a?(Integer) && value.between?(1, 65_535)
        raise ConfigError, "#{where}.port must be an integer between 1 and 65535"
      end

      value
    end

    def self.parse_path(raw, key, fallback, where)
      value = raw.fetch(key, fallback)
      unless value.is_a?(String) && value.start_with?("/")
        raise ConfigError, "#{where}.#{key} must be a string beginning with /"
      end

      value
    end

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

    def enabled?
      @enabled
    end

    def wants_password?
      !@username.nil?
    end

    # RTSP URL for the given stream path. +password+ may be nil for anonymous
    # cameras. Credentials are percent-encoded; they exist only inside the
    # returned string and are never logged or persisted by this class.
    def url_for(path, password = nil)
      authority = "#{@host}:#{@port}"
      if @username
        authority = "#{self.class.percent_encode(@username)}:#{self.class.percent_encode(password.to_s)}@#{authority}"
      end
      "rtsp://#{authority}#{path}"
    end

    def mainstream_url(password = nil)
      url_for(@main_path, password)
    end

    def substream_url(password = nil)
      url_for(@sub_path, password)
    end

    # Percent-encode everything outside RFC 3986's unreserved set so usernames
    # and passwords containing :, @, /, %, spaces, or UTF-8 stay intact.
    def self.percent_encode(value)
      value.b.gsub(/[^A-Za-z0-9._~-]/n) { |byte| format("%%%02X", byte.ord) }
    end
  end
end
