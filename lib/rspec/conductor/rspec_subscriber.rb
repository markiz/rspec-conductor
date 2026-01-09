module RSpec
  module Conductor
    # Technically this is a **Formatter**, as in RSpec Formatter, but that was too confusing,
    # and there is another thing called formatter in this library. Hence, Subscriber.
    class RSpecSubscriber
      RSpec::Core::Formatters.register self,
        :example_passed,
        :example_failed,
        :example_pending

      def initialize(socket, file, shutdown_check)
        @socket = socket
        @file = file
        @shutdown_check = shutdown_check
      end

      def example_passed(notification)
        @socket.send_message(
          type: :example_passed,
          file: @file,
          description: notification.example.full_description,
          location: notification.example.location,
          run_time: notification.example.execution_result.run_time
        )
        @shutdown_check.call
      end

      def example_failed(notification)
        ex = notification.example
        @socket.send_message(
          type: :example_failed,
          file: @file,
          description: ex.full_description,
          location: ex.location,
          run_time: ex.execution_result.run_time,
          exception_class: ex.execution_result.exception&.class&.name,
          message: ex.execution_result.exception&.message,
          backtrace: format_backtrace(ex.execution_result.exception&.backtrace, ex.metadata)
        )
        @shutdown_check.call
      end

      def example_pending(notification)
        ex = notification.example
        @socket.send_message(
          type: :example_pending,
          file: @file,
          description: ex.full_description,
          location: ex.location,
          pending_message: ex.execution_result.pending_message
        )
        @shutdown_check.call
      end

      # This one is invoked by rspec-retry, hence the slightly different api from example_* methods
      def retry(ex)
        @socket.send_message(
          type: :example_retried,
          description: ex.full_description,
          location: ex.location,
          exception_class: ex.exception&.class&.name,
          message: ex.exception&.message,
          backtrace: format_backtrace(ex.exception&.backtrace, ex.metadata)
        )
      end

      private

      def format_backtrace(backtrace, example_metadata = nil)
        RSpec::Core::BacktraceFormatter.new.format_backtrace(backtrace || [], example_metadata || {})
      end
    end
  end
end
