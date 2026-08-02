# frozen_string_literal: true

module RSpec
  module Conductor
    class WorkerProcess
      def self.spawn(number:, test_env_number:, on_message:, on_stdout: nil, on_stderr: nil, **worker_init_args)
        worker_process = new(number: number, on_message: on_message)

        child_process = Util::ChildProcess.fork(on_stdout: on_stdout, on_stderr: on_stderr, on_message: proc { worker_process.handle_message }) do |_, child_socket|
          ENV["TEST_ENV_NUMBER"] = test_env_number
          Worker.new(
            worker_number: number,
            socket: Protocol::Socket.new(child_socket),
            **worker_init_args
          ).run
        end

        worker_process.child_process = child_process
        worker_process
      end

      def self.tick_all(worker_processes)
        Util::ChildProcess.tick_all(worker_processes.map(&:child_process))
      end

      def self.wait_all(worker_processes)
        Util::ChildProcess.wait_all(worker_processes.map(&:child_process))
      end

      attr_reader :number
      attr_accessor :current_spec, :child_process, :status

      def initialize(number:, on_message: nil)
        @number = number
        @on_message = on_message
        @status = :running
      end

      def handle_message
        message = receive_message
        unless message
          socket.close
          return
        end

        @on_message&.call(self, message)
      end

      def send_message(message)
        socket.send_message(message)
      end

      def receive_message
        socket.receive_message
      end

      def socket
        @socket ||= Protocol::Socket.new(child_process.message_socket)
      end

      def pid
        child_process.pid
      end

      def shut_down(status)
        return unless running?

        @status = status
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
