# frozen_string_literal: true

module RSpec
  module Conductor
    WorkerProcess = Struct.new(:pid, :child_process, :number, :status, :socket, :current_spec, keyword_init: true) do
      def self.spawn(number:, test_env_number:, on_stdout: nil, on_stderr: nil, **worker_init_args)
        parent_socket, child_socket = Socket.pair(:UNIX, :STREAM, 0)
        child_process = Util::ChildProcess.fork(on_stdout: on_stdout, on_stderr: on_stderr) do
          ENV["TEST_ENV_NUMBER"] = test_env_number
          parent_socket.close
          Worker.new(
            worker_number: number,
            socket: Protocol::Socket.new(child_socket),
            **worker_init_args
          ).run
        end
        child_socket.close

        new(
          pid: child_process.pid,
          child_process: child_process,
          number: number,
          status: :running,
          socket: Protocol::Socket.new(parent_socket),
          current_spec: nil
        )
      end

      def shut_down(status)
        return unless running?

        self.status = status
        socket.close
      end

      def running?
        status == :running
      end

      def hash
        [number].hash
      end

      def eql?(other)
        other.is_a?(self.class) && other.number == number
      end
    end
  end
end
