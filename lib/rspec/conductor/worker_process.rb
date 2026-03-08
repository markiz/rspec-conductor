# frozen_string_literal: true

require "socket"

module RSpec
  module Conductor
    WorkerProcess = Struct.new(:pid, :child_process, :number, :on_message, :status, :socket, :current_spec, keyword_init: true) do
      def self.spawn(number:, test_env_number:, on_message:, on_stdout: nil, on_stderr: nil, **worker_init_args)
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
          on_message: on_message,
          number: number,
          status: :running,
          socket: Protocol::Socket.new(parent_socket),
          current_spec: nil
        )
      end

      def self.tick_all(worker_processes)
        worker_processes_by_io = worker_processes.select(&:running?).to_h { |w| [w.socket.io, w] }
        readable_ios, = IO.select(worker_processes_by_io.keys, nil, nil, 0)
        readable_ios&.each { |io| worker_processes_by_io.fetch(io).handle_message }
        Util::ChildProcess.tick_all(worker_processes.map(&:child_process))
      end

      def self.wait_all(worker_processes)
        Util::ChildProcess.wait_all(worker_processes.map(&:child_process))
      end

      def handle_message
        message = receive_message
        return unless message && on_message

        on_message.call(self, message)
      end

      def send_message(message)
        socket.send_message(message)
      end

      def receive_message
        socket.receive_message
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
