module RSpec
  module Conductor
    WorkerProcess = Struct.new(:pid, :number, :status, :socket, :current_spec, keyword_init: true) do
      def hash
        [number].hash
      end

      def eql?(other)
        other.is_a?(self.class) && other.number == number
      end
    end
  end
end
