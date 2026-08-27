# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::ChildProcess do
  describe ".spawn" do
    subject(:spawn_process) { described_class.spawn(argv) }

    let(:argv) { ["sh", "-c", "echo 'spawned'; echo 'err' >&2"] }

    it "spawns a child process and returns pid with stderr readable pipe" do
      pid, err_pipe = spawn_process

      expect(pid).to be_a(Integer)
      expect(pid).to be > 0
      expect(err_pipe).to be_a(IO)

      described_class.reap(pid, 0)
      stderr_content = err_pipe.read
      err_pipe.close

      expect(stderr_content).to include("err")
    end
  end

  describe ".reap" do
    subject(:reap_process) { described_class.reap(pid, Process::WNOHANG) }

    context "when child has already exited" do
      let(:pid) { Process.spawn("sh", "-c", "exit 0") }

      before { Process.waitpid(pid) }

      it "handles Errno::ECHILD gracefully and returns nil status" do
        expect(reap_process).to eq([pid, nil])
      end
    end

    context "when child is waiting to be reaped" do
      let(:pid) { Process.spawn("sh", "-c", "exit 42") }

      it "reaps the process and returns the status" do
        _waited_pid, status = described_class.reap(pid, 0)

        expect(status.exitstatus).to eq(42)
      end
    end
  end

  describe ".kill" do
    subject(:kill_process) { described_class.kill(pid, "TERM") }

    let(:pid) { Process.spawn("sh", "-c", "sleep 10") }

    after do
      begin
        Process.kill("KILL", pid)
      rescue StandardError
        nil
      end
      begin
        Process.waitpid(pid, Process::WNOHANG)
      rescue StandardError
        nil
      end
    end

    context "when process is running" do
      it "delivers the signal successfully" do
        expect(kill_process).to be true
      end
    end

    context "when process does not exist" do
      let(:pid) { 999_999 }

      it "returns false without raising an error" do
        expect(kill_process).to be false
      end
    end
  end

  describe ".prepare_child" do
    subject(:prepare_child) { described_class.prepare_child(Process.ppid) }

    it "runs without raising exceptions" do
      expect { prepare_child }.not_to raise_error
    end
  end
end
