# frozen_string_literal: true

# RSpec doesn't provide us with a good way to handle before/after suite hooks,
# doing what we can here
class RSpec::Core::Configuration
  def __run_before_suite_hooks
    RSpec.current_scope = :before_suite_hook
    run_suite_hooks("a `before(:suite)` hook", @before_suite_hooks)
  end

  def __run_after_suite_hooks
    RSpec.current_scope = :after_suite_hook
    run_suite_hooks("an `after(:suite)` hook", @after_suite_hooks)
  end
end

module RSpec
  module Conductor
    class Worker
      def initialize(worker_number:, socket:, rspec_args: [], verbose: false)
        @worker_number = worker_number
        @socket = socket
        @rspec_args = rspec_args
        @verbose = verbose
        @message_queue = []
      end

      def run
        suppress_output unless @verbose
        debug "Worker #{@worker_number} starting"
        setup_load_path
        initialize_rspec

        loop do
          debug "Waiting for message"
          message = @message_queue.shift || @socket.receive_message

          unless message
            debug "Received nil message, exiting"
            break
          end

          debug "Received: #{message.inspect}"

          case message[:type].to_sym
          when :worker_assigned_spec
            debug "Running spec: #{message[:file]}"
            run_spec(message[:file])
            debug "Finished spec: #{message[:file]}"
            break if @shutdown_requested
          when :shutdown
            debug "Shutdown received"
            @shutdown_requested = true
            break
          end
        end

        debug "Worker #{@worker_number} shutting down, running after(:suite) hooks and exiting"
        RSpec.configuration.__run_after_suite_hooks
      rescue StandardError => e
        debug "Worker crashed: #{e.class}: #{e.message}"
        debug e.backtrace.join("\n")
        raise
      ensure
        @socket.close
      end

      private

      def setup_load_path
        parsed_options.configure(RSpec.configuration)
        default_path = RSpec.configuration.default_path || "spec"

        spec_path = File.expand_path("spec", Conductor.root)
        default_full_path = File.expand_path(default_path, Conductor.root)

        $LOAD_PATH.unshift(spec_path) if Dir.exist?(spec_path) && !$LOAD_PATH.include?(spec_path)

        if default_full_path != spec_path && Dir.exist?(default_full_path)
          $LOAD_PATH.unshift(default_full_path)
        end

        debug "Load path (spec dirs): #{$LOAD_PATH.grep(/spec/)}"
      end

      def suppress_output
        $stdout.reopen(null_io_out)
        $stderr.reopen(null_io_out)
        $stdin.reopen(null_io_in)
      end

      def initialize_rspec
        rails_helper = File.expand_path("rails_helper.rb", Conductor.root)
        spec_helper = File.expand_path("spec_helper.rb", Conductor.root)
        if File.exist?(rails_helper)
          debug "Requiring rails_helper to boot Rails..."
          require rails_helper
        elsif File.exist?(spec_helper)
          debug "Requiring spec_helper..."
          require spec_helper
        else
          debug "Could detect neither rails_helper nor spec_helper"
        end

        debug "RSpec initialized, running before(:suite) hooks"
        RSpec.configuration.__run_before_suite_hooks
      end

      def run_spec(file)
        RSpec.world.reset
        RSpec.configuration.reset_reporter
        RSpec.configuration.files_or_directories_to_run = []
        setup_formatter(ConductorFormatter.new(@socket, file, -> { check_for_shutdown }))

        begin
          debug "Loading spec file: #{file}"
          debug "Exclusion filters: #{RSpec.configuration.exclusion_filter.description}"
          debug "Inclusion filters: #{RSpec.configuration.inclusion_filter.description}"
          load file
          debug "Example groups after load: #{RSpec.world.example_groups.count}"

          example_groups = RSpec.world.ordered_example_groups
          debug "Example count: #{RSpec.world.example_count}"

          RSpec.configuration.reporter.report(RSpec.world.example_count) do |reporter|
            example_groups.each { |g| g.run(reporter) }
          end

          @socket.send_message(
            type: :spec_complete,
            file: file
          )
        rescue StandardError => e
          debug "Spec error: #{e.class}: #{e.message}"
          debug "Backtrace: #{e.backtrace.join("\n")}"
          @socket.send_message(
            type: :spec_error,
            file: file,
            error: e.message,
            backtrace: e.backtrace
          )
        end
      end

      def check_for_shutdown
        return unless @socket.io.wait_readable(0)

        message = @socket.receive_message
        return unless message

        if message[:type].to_sym == :shutdown
          debug "Shutdown received mid-spec"
          @shutdown_requested = true
          RSpec.world.wants_to_quit = true
        else
          debug "Non shutdown message: #{message}"
          @message_queue << message
        end
      end

      def parsed_options
        @parsed_options ||= RSpec::Core::ConfigurationOptions.new(@rspec_args)
      end

      def setup_formatter(conductor_formatter)
        RSpec.configuration.output_stream = null_io_out
        RSpec.configuration.error_stream = null_io_out
        RSpec.configuration.formatter_loader.formatters.clear
        RSpec.configuration.add_formatter(conductor_formatter)
      end

      def debug(message)
        $stderr.puts "[worker #{@worker_number}] #{message}"
      end

      def null_io_out
        @null_io_out ||= File.open(File::NULL, "w")
      end

      def null_io_in
        @null_io_in ||= File.open(File::NULL, "r")
      end
    end

    class ConductorFormatter
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
