# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe VisionHub::RuntimeDirectory do
  describe ".ensure_secure_dir!" do
    it "creates a directory with 0700 permissions if nonexistent" do
      Dir.mktmpdir do |base|
        target = File.join(base, "vision-hub")
        described_class.ensure_secure_dir!(target)

        expect(File.directory?(target)).to be true
        expect(format("%o", File.stat(target).mode)).to end_with("700")
      end
    end

    it "fixes permissions to 0700 if directory exists with wide permissions" do
      Dir.mktmpdir do |base|
        target = File.join(base, "vision-hub")
        Dir.mkdir(target, 0o777)
        described_class.ensure_secure_dir!(target)

        expect(format("%o", File.stat(target).mode)).to end_with("700")
      end
    end

    it "rejects symlinks" do
      Dir.mktmpdir do |base|
        real_dir = File.join(base, "real")
        symlink_dir = File.join(base, "link")
        Dir.mkdir(real_dir, 0o700)
        File.symlink(real_dir, symlink_dir)

        expect do
          described_class.ensure_secure_dir!(symlink_dir)
        end.to raise_error(/symlink/)
      end
    end

    it "rejects non-directories" do
      Dir.mktmpdir do |base|
        file_path = File.join(base, "file")
        File.write(file_path, "test")

        expect do
          described_class.ensure_secure_dir!(file_path)
        end.to raise_error(/not a directory/)
      end
    end
  end

  describe ".cleanup_dir!" do
    it "removes jpg and ffconcat files from the runtime directory" do
      Dir.mktmpdir do |dir|
        jpg = File.join(dir, "front.jpg")
        concat = File.join(dir, "front.sub.ffconcat")
        other = File.join(dir, "keep.txt")
        File.write(jpg, "frame")
        File.write(concat, "playlist")
        File.write(other, "keep")

        described_class.cleanup_dir!(dir)

        expect(File.exist?(jpg)).to be false
        expect(File.exist?(concat)).to be false
        expect(File.exist?(other)).to be true
      end
    end
  end

  describe ".clean_file!" do
    it "safely removes existing files and symlinks" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "target.jpg")
        File.write(file, "content")
        described_class.clean_file!(file)
        expect(File.exist?(file)).to be false
      end
    end
  end
end
