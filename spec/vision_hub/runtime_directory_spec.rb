# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe VisionHub::RuntimeDirectory do
  describe ".ensure_secure_dir!" do
    subject(:ensure_dir) { described_class.ensure_secure_dir!(target) }

    let(:base_dir) { Dir.mktmpdir }
    let(:target) { File.join(base_dir, "vision-hub") }

    after { FileUtils.remove_entry(base_dir) if File.directory?(base_dir) }

    context "when directory does not exist" do
      it "creates a directory with 0700 permissions" do
        ensure_dir

        expect(File.directory?(target)).to be true
        expect(target).to have_file_mode("700")
      end
    end

    context "when directory exists with wide permissions" do
      before { Dir.mkdir(target, 0o777) }

      it "restricts permissions to 0700" do
        ensure_dir

        expect(target).to have_file_mode("700")
      end
    end

    context "when target is a symlink" do
      let(:real_dir) { File.join(base_dir, "real") }

      before do
        Dir.mkdir(real_dir, 0o700)
        File.symlink(real_dir, target)
      end

      it "raises an error rejecting symlinks" do
        expect { ensure_dir }.to raise_error(/symlink/)
      end
    end

    context "when target is a regular file" do
      before { File.write(target, "test") }

      it "raises an error rejecting non-directories" do
        expect { ensure_dir }.to raise_error(/not a directory/)
      end
    end
  end

  describe ".cleanup_dir!" do
    subject(:cleanup) { described_class.cleanup_dir!(dir) }

    let(:dir) { Dir.mktmpdir }
    let(:jpg) { File.join(dir, "front.jpg") }
    let(:concat) { File.join(dir, "front.sub.ffconcat") }
    let(:other) { File.join(dir, "keep.txt") }

    before do
      File.write(jpg, "frame")
      File.write(concat, "playlist")
      File.write(other, "keep")
    end

    after { FileUtils.remove_entry(dir) if File.directory?(dir) }

    context "when directory contains stale frames and playlists" do
      it "removes jpg and ffconcat files while preserving unrelated files" do
        cleanup

        expect(File.exist?(jpg)).to be false
        expect(File.exist?(concat)).to be false
        expect(File.exist?(other)).to be true
      end
    end
  end

  describe ".clean_file!" do
    subject(:clean_file) { described_class.clean_file!(file) }

    let(:dir) { Dir.mktmpdir }
    let(:file) { File.join(dir, "target.jpg") }

    before { File.write(file, "content") }
    after { FileUtils.remove_entry(dir) if File.directory?(dir) }

    context "when file exists" do
      it "safely removes the file" do
        clean_file

        expect(File.exist?(file)).to be false
      end
    end
  end
end
