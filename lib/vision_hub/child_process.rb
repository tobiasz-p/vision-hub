# frozen_string_literal: true

module VisionHub
  # Real process primitives behind the injectable seams of FramePump: spawning
  # with crash-isolation guarantees, non-blocking reap, and signal escalation.
  module ChildProcess
    # Spawns +argv+ with its stderr on a pipe the caller owns.
    #
    # The child forks so it can request PR_SET_PDEATHSIG before exec: if the
    # daemon dies — even by SIGKILL — the kernel delivers SIGTERM to every
    # ffmpeg still running, so no decoder outlives the shell session. The
    # child also puts itself into its own process group, letting callers
    # signal the whole tree. Platforms without fork fall back to
    # Process.spawn's pgroup option (losing PDEATHSIG, keeping pgroup).
    #
    # @param argv [Array<String>] command line arguments to execute
    # @return [Array(Integer, IO)] child PID and readable pipe IO for stderr
    def self.spawn(argv)
      rd, wr = IO.pipe
      parent_pid = Process.pid
      pid =
        begin
          fork do
            rd.close
            $stderr.reopen(wr)
            wr.close
            prepare_child(parent_pid)
            Process.exec(argv.fetch(0), *argv.drop(1))
          end
        rescue NotImplementedError
          Process.spawn(*argv, pgroup: true, err: wr)
        end
      wr.close
      [pid, rd]
    end

    # Non-blocking or flagged process wait.
    #
    # @param pid [Integer] child process ID
    # @param flags [Integer] waitpid flags (defaults to Process::WNOHANG)
    # @return [Array(Integer, Process::Status), Array(Integer, nil), nil] waitpid result
    def self.reap(pid, flags = Process::WNOHANG)
      Process.waitpid2(pid, flags)
    rescue Errno::ECHILD
      [pid, nil]
    end

    # Signals the process group first, falling back to the bare pid. Returns
    # whether the signal was delivered anywhere.
    #
    # @param pid [Integer] process ID
    # @param name [String, Integer, Symbol] signal name or number
    # @return [Boolean] true if signal was successfully delivered
    def self.kill(pid, name)
      delivered = begin
        Process.kill(name, -pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end
      return delivered if delivered

      begin
        Process.kill(name, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end
    end

    # Prepares child process environment prior to exec (PDEATHSIG and process group).
    #
    # @param parent_pid [Integer] PID of the parent process
    # @return [void]
    def self.prepare_child(parent_pid)
      require "fiddle"
      libc = Fiddle.dlopen(nil)
      prctl = Fiddle::Function.new(libc["prctl"], [Fiddle::TYPE_INT] * 5, Fiddle::TYPE_INT)
      prctl.call(1, 15, 0, 0, 0) # PR_SET_PDEATHSIG, SIGTERM
      Process.exit!(1) if Process.ppid != parent_pid
      Process.setpgid(0, 0)
    rescue StandardError, LoadError
      nil
    end
  end
end
