# frozen_string_literal: true

require "English"
require "socket"
require "json"

module RSpec
  module Conductor
    class Server
      MAX_SEED = 2**16
      WORKER_POLL_INTERVAL = 0.01

      # @option worker_count [Integer] How many workers to spin
      # @option rspec_args [Array<String>] A list of rspec options
      # @option worker_number_offset [Integer] Start worker numbering with an offset
      # @option prefork_require [String] File required prior to forking
      # @option postfork_require [String, Symbol] File required after forking
      # @option first_is_1 [Boolean] TEST_ENV_NUMBER for the first worker is "1" instead of ""
      # @option seed [Integer] Set a predefined starting seed
      # @option fail_fast_after [Integer, NilClass] Shut down the workers after a certain number of failures
      # @option formatter [String] Use a certain formatter
      # @option verbose [Boolean] Use especially verbose output
      # @option display_retry_backtraces [Boolean] Display backtraces for specs retried via rspec-retry
      def initialize(worker_count:, rspec_args:, **opts)
        @worker_count = worker_count
        @worker_number_offset = opts.fetch(:worker_number_offset, 0)
        @prefork_require = opts.fetch(:prefork_require, nil)
        @postfork_require = opts.fetch(:postfork_require, nil)
        @first_is_one = opts.fetch(:first_is_1, false)
        @seed = opts[:seed] || (Random.new_seed % MAX_SEED)
        @fail_fast_after = opts[:fail_fast_after]
        @display_retry_backtraces = opts.fetch(:display_retry_backtraces, false)
        @verbose = opts.fetch(:verbose, false)

        @rspec_args = rspec_args
        @worker_processes = {}
        @spec_queue = []
        @formatter = case opts[:formatter]
                     when "ci"
                       Formatters::CI.new
                     when "fancy"
                       Formatters::Fancy.new(worker_count: worker_count)
                     when "plain"
                       Formatters::Plain.new
                     else
                       (!@verbose && Formatters::Fancy.recommended?) ? Formatters::Fancy.new : Formatters::Plain.new
                     end
        @results = Results.new
      end

      def run
        setup_signal_handlers
        build_spec_queue
        preload_application

        $stdout.sync = true
        puts "RSpec Conductor starting with #{@worker_count} workers (seed: #{@seed})"
        puts "Running #{@spec_queue.size} spec files\n\n"

        start_workers
        run_event_loop
        @results.suite_complete

        print_summary
        exit_with_status
      end

      private

      def preload_application
        if !@prefork_require
          debug "Prefork require not set, skipping..."
          return
        end

        preload = File.expand_path(@prefork_require, Conductor.root)

        if File.exist?(preload)
          debug "Preloading #{@prefork_require}..."
          require preload
        else
          debug "#{@prefork_require} not found, skipping..."
        end

        debug "Application preloaded, autoload paths configured"
      end

      def setup_signal_handlers
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            @worker_processes.any? ? initiate_shutdown : Kernel.exit(1)
          end
        end
      end

      def initiate_shutdown
        return if @results.shutting_down?

        @results.shut_down
        puts "Shutting down..."
        @worker_processes.each_value { |w| w.socket&.send_message({ type: :shutdown }) }
      end

      def build_spec_queue
        paths = extract_paths_from_args

        config = RSpec::Core::Configuration.new
        config.files_or_directories_to_run = paths

        @spec_queue = config.files_to_run.shuffle(random: Random.new(@seed))
        @results.spec_files_total = @spec_queue.size
      end

      def parsed_rspec_args
        @parsed_rspec_args ||= RSpec::Core::ConfigurationOptions.new(@rspec_args)
      end

      def extract_paths_from_args
        files = parsed_rspec_args.options[:files_or_directories_to_run] || []
        files.empty? ? [File.join(Conductor.root, "spec/")] : files
      end

      def start_workers
        @worker_count.times do |i|
          spawn_worker(@worker_number_offset + i + 1)
        end
      end

      def spawn_worker(worker_number)
        parent_socket, child_socket = Socket.pair(:UNIX, :STREAM, 0)

        debug "Spawning worker #{worker_number}"

        pid = fork do
          parent_socket.close

          ENV["TEST_ENV_NUMBER"] = if @first_is_one || worker_number != 1
                                     worker_number.to_s
                                   else
                                     ""
                                   end

          Worker.new(
            worker_number: worker_number,
            socket: Protocol::Socket.new(child_socket),
            rspec_args: @rspec_args,
            verbose: @verbose,
            postfork_require: @postfork_require,
          ).run
        end

        child_socket.close
        debug "Worker #{worker_number} started with pid #{pid}"

        @worker_processes[pid] = WorkerProcess.new(
          pid: pid,
          number: worker_number,
          status: :running,
          socket: Protocol::Socket.new(parent_socket),
          current_spec: nil,
        )
        assign_work(@worker_processes[pid])
      end

      def run_event_loop
        until @worker_processes.empty?
          worker_processes_by_io = @worker_processes.values.to_h { |w| [w.socket.io, w] }
          readable_ios, = IO.select(worker_processes_by_io.keys, nil, nil, WORKER_POLL_INTERVAL)
          readable_ios&.each { |io| handle_worker_message(worker_processes_by_io.fetch(io)) }
          reap_workers
        end
      end

      def handle_worker_message(worker_process)
        message = worker_process.socket.receive_message
        return unless message

        debug "Worker #{worker_process.number}: #{message[:type]}"

        case message[:type].to_sym
        when :example_passed
          @results.example_passed
        when :example_failed
          @results.example_failed(message)

          if @fail_fast_after && @results.failed >= @fail_fast_after
            debug "Shutting down after #{@results.failed} failures"
            initiate_shutdown
          end
        when :example_pending
          @results.example_pending
        when :example_retried
          if @display_retry_backtraces
            puts "\nExample #{message[:description]} retried:\n  #{message[:location]}\n  #{message[:exception_class]}: #{message[:message]}\n#{message[:backtrace].map { "    #{_1}" }.join("\n")}\n"
          end
        when :spec_complete
          @results.spec_file_complete
          worker_process.current_spec = nil
          assign_work(worker_process)
        when :spec_error
          @results.spec_file_error(message)
          debug "Spec error details: #{message[:error]}"
          worker_process.current_spec = nil
          assign_work(worker_process)
        when :spec_interrupted
          debug "Spec interrupted: #{message[:file]}"
          worker_process.current_spec = nil
        end
        @formatter.handle_worker_message(worker_process, message, @results)
      end

      def assign_work(worker_process)
        spec_file = @spec_queue.shift

        if @results.shutting_down? || !spec_file
          debug "No more work for worker #{worker_process.number}, sending shutdown"
          worker_process.socket.send_message({ type: :shutdown })
          cleanup_worker_process(worker_process)
        else
          @results.spec_file_assigned
          worker_process.current_spec = spec_file
          debug "Assigning #{spec_file} to worker #{worker_process.number}"
          message = { type: :worker_assigned_spec, file: spec_file }
          worker_process.socket.send_message(message)
          @formatter.handle_worker_message(worker_process, message, @results)
        end
      end

      def cleanup_worker_process(worker_process, status: :shut_down)
        @worker_processes.delete(worker_process.pid)
        worker_process.socket.close
        worker_process.status = status
        @formatter.handle_worker_message(worker_process, { type: :worker_shut_down }, @results)
        Process.wait(worker_process.pid)
      rescue Errno::ECHILD
        nil
      end

      def reap_workers
        dead_worker_processes = @worker_processes.each_with_object([]) do |(pid, worker), memo|
          result = Process.waitpid(pid, Process::WNOHANG)
          memo << [worker, $CHILD_STATUS] if result
        end

        dead_worker_processes.each do |worker_process, exitstatus|
          cleanup_worker_process(worker_process, status: :terminated)
          @results.worker_crashed
          debug "Worker #{worker_process.number} exited with status #{exitstatus.exitstatus}, signal #{exitstatus.termsig}"
        end
      rescue Errno::ECHILD
        nil
      end

      def print_summary
        puts "\n\n"
        puts "Randomized with seed #{@seed}"
        puts "#{colorize("#{@results.passed} passed", :green)}, #{colorize("#{@results.failed} failed", :red)}, #{colorize("#{@results.pending} pending", :yellow)}"
        puts colorize("Worker crashes: #{@results.worker_crashes}", :red) if @results.worker_crashes.positive?

        if @results.errors.any?
          puts "\nFailures:\n\n"
          @results.errors.each_with_index do |error, i|
            puts "  #{i + 1}) #{error[:description]}"
            puts "     #{error[:location]}"
            puts "     #{error[:message]}" if error[:message]
            if error[:backtrace]&.any?
              puts "     Backtrace:"
              error[:backtrace].each { |line| puts "       #{line}" }
            end
            puts
          end
        end

        puts "Specs took: #{@results.specs_runtime.round(2)}s"
        puts "Total runtime: #{@results.total_runtime.round(2)}s"
        puts "Suite: #{@results.success? ? colorize("PASSED", :green) : colorize("FAILED", :red)}"
      end

      def colorize(string, color)
        $stdout.tty? ? Util::ANSI.colorize(string, color) : string
      end

      def exit_with_status
        Kernel.exit(@results.success? ? 0 : 1)
      end

      def debug(message)
        return unless @verbose

        $stderr.puts "[conductor] #{message}"
      end
    end
  end
end
