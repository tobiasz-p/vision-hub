# frozen_string_literal: true

require "open3"

module VisionHub
  # Looks camera passwords up in the user's keyring through secret-tool.
  #
  # The password travels only on stdout of the child process; it never appears
  # in an argument list, a log line, or an exception message.
  class SecretStore
    APPLICATION_ATTR = "application"
    CAMERA_ATTR = "camera"

    # Returns [ok, stdout]. Kept injectable so specs can stub lookups without
    # touching gnome-keyring.
    DEFAULT_RUNNER = lambda { |argv|
      stdout, stderr, status = Open3.capture3(*argv)
      [status.success?, stdout, stderr]
    }

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
    def lookup(camera_id)
      cached = @cache[camera_id]
      return cached unless cached.nil?

      value = fetch_keyring(camera_id) || (camera_id == "default" ? nil : lookup("default"))
      @cache[camera_id] = value unless value.nil?
      value
    end

    def configured?(camera_id)
      !lookup(camera_id).nil?
    end

    def clear_cache!
      @cache.clear
    end

    # The exact command for the UI to show when a camera is unconfigured.
    # Contains only attributes, never a secret.
    def self.store_command(application_id, camera_id)
      "secret-tool store --label='VisionHub camera #{camera_id}' " \
        "#{APPLICATION_ATTR} #{application_id} #{CAMERA_ATTR} #{camera_id}"
    end

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
