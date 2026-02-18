# frozen_string_literal: true

require_relative 'ext/rspec'

module RSpec
  module Conductor
    class Worker
      def initialize(worker_number:, socket:, rspec_args: [], verbose: false, postfork_require: :spec_helper)
        @worker_number = worker_number
        @socket = socket
        @rspec_args = rspec_args
        @verbose = verbose
        @postfork_require = postfork_require

        @message_queue = []
      end

      def run
        suppress_output unless @verbose
        debug "Worker #{@worker_number} starting"
        setup_load_path
        require_postfork_preloads

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
        @default_path = RSpec.configuration.default_path || "spec"
        @default_full_path = File.expand_path(@default_path)

        add_load_path(File.expand_path("lib"))
        add_load_path(@default_full_path)

        debug "Load path: #{$LOAD_PATH.inspect}"
      end

      def add_load_path(path)
        return unless File.directory?(path)
        return if $LOAD_PATH.include?(path)

        $LOAD_PATH.unshift(path)
      end

      def suppress_output
        $stdout.reopen(null_io_out)
        $stderr.reopen(null_io_out)
        $stdin.reopen(null_io_in)
      end

      def require_postfork_preloads
        if @postfork_require == :spec_helper
          rails_helper = File.expand_path("rails_helper.rb", @default_full_path)
          spec_helper = File.expand_path("spec_helper.rb", @default_full_path)
          if File.exist?(rails_helper)
            debug "Requiring rails_helper to boot Rails..."
            require rails_helper
          elsif File.exist?(spec_helper)
            debug "Requiring spec_helper..."
            require spec_helper
          else
            debug "Neither rails_helper, nor spec_helper found, skipping..."
          end
        elsif @postfork_require
          required_file = File.expand_path(@postfork_require)
          if File.exist?(required_file)
            debug "Requiring #{required_file}..."
            require required_file
          else
            debug "#{required_file} not found, skipping..."
          end
        else
          debug "Skipping postfork require..."
        end

        debug "RSpec initialized, running before(:suite) hooks"
        RSpec.configuration.__run_before_suite_hooks
      end

      def run_spec(file)
        RSpec.world.reset
        RSpec.configuration.reset
        RSpec.configuration.files_or_directories_to_run = [file]
        RSpec.configuration.output_stream = null_io_out
        RSpec.configuration.error_stream = null_io_out
        RSpec.configuration.formatter_loader.formatters.clear
        RSpec.configuration.add_formatter(RSpecSubscriber.new(@socket, file, -> { check_for_shutdown }))
        parsed_options.configure(RSpec.configuration)
        RSpec.configuration.files_to_run # this seemingly random line is necessary for rspec to set up the inclusion filters (e.g. hello_spec.rb:123 -> the :123 part is an inclusion filter)

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
        @parsed_options ||= RSpec::Core::ConfigurationOptions.new(@rspec_args).tap { |co| co.options.delete(:requires) }
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
  end
end
