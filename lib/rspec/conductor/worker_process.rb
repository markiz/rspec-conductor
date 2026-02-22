module RSpec
  module Conductor
    WorkerProcess = Struct.new(:pid, :number, :status, :socket, :current_spec, keyword_init: true) do
      def self.spawn(number:, test_env_number:, **worker_init_args)
        parent_socket, child_socket = Socket.pair(:UNIX, :STREAM, 0)
        pid = fork do
          ENV["TEST_ENV_NUMBER"] = test_env_number
          parent_socket.close
          Worker.new(
            worker_number: number,
            socket: Protocol::Socket.new(child_socket),
            **worker_init_args
          ).run
        end
        child_socket.close

        new(pid:, number:, status: :running, socket: Protocol::Socket.new(parent_socket), current_spec: nil)
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
