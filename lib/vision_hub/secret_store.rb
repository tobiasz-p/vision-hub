# frozen_string_literal: true

require "open3"

module VisionHub
  # Looks camera passwords up in the user's keyring through secret-tool.
  #
  # The password travels only on stdout of the child process; it never appears
  # in an argument list, a log line, or an exception message.
  class SecretStore
    # Keyring attribute name for the application identifier.
    # @return [String]
    APPLICATION_ATTR = "application"

    # Keyring attribute name for the camera identifier.
    # @return [String]
    CAMERA_ATTR = "camera"

    # Default secret-tool execution runner. Returns `[ok, stdout, stderr]`.
    # Kept injectable so specs can stub lookups without touching gnome-keyring.
    # @return [Proc]
    DEFAULT_RUNNER = lambda { |argv|
      stdout, stderr, status = Open3.capture3(*argv)
      [status.success?, stdout, stderr]
    }

    # Initializes a SecretStore with a keyring application ID and lookup runner.
    #
    # @param application_id [String] keyring application attribute namespace
    # @param runner [#call] command execution callable taking argv and returning `[Boolean, String, String]`
    def initialize(application_id: DEFAULT_APPLICATION_ID, runner: DEFAULT_RUNNER)
      @application_id = application_id
      @runner = runner
      @cache = {}
    end

    # The stored password for +camera_id+, or nil when the keyring has no
    # entry (or the lookup fails). Positive results are cached: reconnecting
    # cameras must not hammer the keyring. Misses are deliberately NOT cached,
    # so an entry added later is picked up by the next unconfigured-retry
    # without a daemon restart.
    #
    # @param camera_id [String] camera identifier
    # @return [String, nil] cleartext password or nil if not found
    def lookup(camera_id)
      cached = @cache[camera_id]
      return cached unless cached.nil?

      value = fetch_keyring(camera_id) || (camera_id == "default" ? nil : lookup("default"))
      @cache[camera_id] = value unless value.nil?
      value
    end

    # Checks if credentials exist for the specified camera (or default fallback).
    #
    # @param camera_id [String] camera identifier
    # @return [Boolean] true if credentials exist
    def configured?(camera_id)
      !lookup(camera_id).nil?
    end

    # Clears the internal lookup cache.
    #
    # @return [void]
    def clear_cache!
      @cache.clear
    end

    # The exact command for the UI to show when a camera is unconfigured.
    # Contains only attributes, never a secret.
    #
    # @param application_id [String] keyring application attribute namespace
    # @param camera_id [String] camera identifier
    # @return [String] shell command string
    def self.store_command(application_id, camera_id)
      "secret-tool store --label='VisionHub camera #{camera_id}' " \
        "#{APPLICATION_ATTR} #{application_id} #{CAMERA_ATTR} #{camera_id}"
    end

    # Generates the store command for a camera using this instance's application ID.
    #
    # @param camera_id [String] camera identifier
    # @return [String] shell command string
    def store_command_for(camera_id)
      self.class.store_command(@application_id, camera_id)
    end

    private

    def fetch_keyring(camera_id)
      ok, stdout = @runner.call(lookup_argv(camera_id))
      ok && !stdout.strip.empty? ? stdout.strip : nil
    end

    def lookup_argv(camera_id)
      ["secret-tool", "lookup", APPLICATION_ATTR, @application_id, CAMERA_ATTR, camera_id]
    end
  end
end
