# frozen_string_literal: true

require "fileutils"

module VisionHub
  # Manages and secures the runtime directory used for tmpfs frames and playlists.
  # Ensures proper ownership, mode (0700), prevents symlink hijacking, and handles cleanup.
  module RuntimeDirectory
    def self.ensure_secure_dir!(dir)
      if File.exist?(dir)
        assert_secure_existing!(dir)
      else
        FileUtils.mkdir_p(dir)
        File.chmod(0o700, dir)
      end
    end

    def self.assert_secure_existing!(dir)
      raise "runtime directory #{dir} is a symlink" if File.symlink?(dir) || File.lstat(dir).symlink?
      raise "runtime directory #{dir} is not a directory" unless File.directory?(dir)

      stat = File.stat(dir)
      raise "runtime directory #{dir} is owned by uid #{stat.uid}, expected #{Process.uid}" if stat.uid != Process.uid

      File.chmod(0o700, dir) if stat.mode.anybits?(0o077)
    end

    def self.cleanup_dir!(dir)
      return unless dir && File.directory?(dir) && !File.symlink?(dir)

      Dir.glob(File.join(dir, "*.{jpg,ffconcat}")).each do |file|
        clean_file!(file)
      end
    rescue StandardError
      nil
    end

    def self.clean_file!(path)
      return unless path

      FileUtils.rm_f(path)
    rescue StandardError
      nil
    end
  end
end
