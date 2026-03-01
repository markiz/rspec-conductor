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
        @first_is_1 = opts.fetch(:first_is_1, Conductor.default_first_is_1?)
        @seed = opts[:seed] || (Random.new_seed % MAX_SEED)
        @fail_fast_after = opts[:fail_fast_after]
        @display_retry_backtraces = opts.fetch(:display_retry_backtraces, false)
        @verbose = opts.fetch(:verbose, false)

        @rspec_args = rspec_args
        @worker_processes = []
        @dead_worker_processes = []
        @spec_queue = []
        @formatter_class = case opts[:formatter]
                           when "ci"
                             Formatters::CI
                           when "fancy"
                             Formatters::Fancy
                           when "plain"
                             Formatters::Plain
                           else
                             (!@verbose && Formatters::Fancy.recommended?) ? Formatters::Fancy : Formatters::Plain
                           end
        @formatter = @formatter_class.new(worker_count: @worker_count)
        @results = Results.new

        $stdout.sync = true
        $stdin.echo = false if $stdin.tty?
        Dir.chdir(Conductor.root)
        ENV["PARALLEL_TEST_GROUPS"] = worker_count.to_s # parallel_tests backward-compatibility
      end

      def run
        setup_signal_handlers
        build_spec_queue
        preload_application

        @formatter.print_startup_banner(worker_count: @worker_count, seed: @seed, spec_files_count: @spec_queue.size)

        start_workers
        run_event_loop
        wait_for_workers_to_exit
        @results.suite_complete

        @formatter.print_summary(@results, seed: @seed, success: success?)
        exit_with_status
      end

      private

      def setup_signal_handlers
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            @worker_processes.any?(&:running?) ? initiate_shutdown : Kernel.exit(1)
          end
        end
      end

      def build_spec_queue
        config_options = RSpec::Core::ConfigurationOptions.new(@rspec_args)
        # a bit of a hack, but if they want to require something explicitly, they should use either --prefork-require or --postfork-require,
        # as it is now, it messes with the preloads
        config_options.options.delete(:requires)
        if config_options.options[:files_or_directories_to_run].empty?
          config_options.options[:files_or_directories_to_run] = ["spec"]
        end
        config = RSpec::Core::Configuration.new
        debug "RSpec config options: #{config_options.inspect}"
        config_options.configure(config)
        debug "RSpec config: #{config.inspect}"
        debug "Files to run: #{config.files_to_run}"
        @spec_queue = config.files_to_run.shuffle(random: Random.new(@seed))
        @results.spec_files_total = @spec_queue.size
      end

      def preload_application
        if !@prefork_require
          debug "Prefork require not set, skipping..."
          return
        end

        preload = File.expand_path(@prefork_require)

        if File.exist?(preload)
          debug "Preloading #{@prefork_require}..."
          require preload
        else
          debug "#{@prefork_require} not found, skipping..."
        end

        debug "Application preloaded, autoload paths configured"
      end

      def start_workers
        @worker_processes = @worker_count.times.map { |i| spawn_worker(@worker_number_offset + i + 1) }
        @worker_processes.each { |wp| assign_work(wp) }
      end

      def run_event_loop
        until @worker_processes.select(&:running?).empty?
          if @shutdown_status == :initiated_graceful
            @shutdown_status = :shutdown_messages_sent
            @formatter.print_shutdown_banner
            @worker_processes.select(&:running?).each do |worker_process|
              worker_process.socket.send_message({ type: :shutdown })
              cleanup_worker_process(worker_process)
            end
          end

          worker_processes_by_io = @worker_processes.select(&:running?).to_h { |w| [w.socket.io, w] }
          readable_ios, = IO.select(worker_processes_by_io.keys, nil, nil, 0)
          readable_ios&.each { |io| handle_worker_message(worker_processes_by_io.fetch(io)) }
          Util::ChildProcess.tick_all(@worker_processes.map(&:child_process))
          reap_workers
        end
      end

      def wait_for_workers_to_exit
        Util::ChildProcess.wait_all(@worker_processes.map(&:child_process))
      end

      def spawn_worker(worker_number)
        debug "Spawning worker #{worker_number}"

        worker_process = WorkerProcess.spawn(
          number: worker_number,
          test_env_number: (@first_is_1 || worker_number != 1) ? worker_number.to_s : "",
          on_stdout: ->(string) { @formatter.handle_worker_stdout(worker_number, string) },
          on_stderr: ->(string) { @formatter.handle_worker_stderr(worker_number, string) },
          debug_io: @verbose ? $stderr : nil,
          rspec_args: @rspec_args,
          postfork_require: @postfork_require,
        )
        debug "Worker #{worker_number} started with pid #{worker_process.pid}"
        worker_process
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

          if @fail_fast_after && @results.examples_failed >= @fail_fast_after
            debug "Shutting down after #{@results.examples_failed} failures"
            initiate_shutdown
          end
        when :example_pending
          @results.example_pending
        when :example_retried
          @formatter.print_retry_message(message) if @display_retry_backtraces
        when :spec_complete
          @results.spec_file_complete
          worker_process.current_spec = nil
          assign_work(worker_process)
        when :spec_error
          @results.spec_file_error(message)
          debug "Spec error details: #{message[:error]}"
          worker_process.current_spec = nil
          assign_work(worker_process)
        end
        @formatter.handle_worker_message(worker_process, message, @results)
      end

      def assign_work(worker_process)
        spec_file = @spec_queue.shift

        if shutting_down? || !spec_file
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
        worker_process.shut_down(status)
        @formatter.handle_worker_message(worker_process, { type: :worker_shut_down }, @results)
      end

      def reap_workers
        dead_worker_processes = @worker_processes.select(&:running?).each_with_object([]) do |worker_process, memo|
          result, status = Process.waitpid2(worker_process.pid, Process::WNOHANG)
          memo << [worker_process, status] if result
        rescue Errno::ECHILD
        end

        dead_worker_processes.each do |worker_process, exitstatus|
          cleanup_worker_process(worker_process, status: :terminated)
          @results.worker_crashed
          debug "Worker #{worker_process.number} exited with status #{exitstatus.exitstatus}, signal #{exitstatus.termsig}"
        end
      end

      def shutting_down?
        !@shutdown_status.nil?
      end

      def initiate_shutdown
        if @shutdown_status.nil?
          @shutdown_status = :initiated_graceful
        elsif @shutdown_status != :initiated_forced && @worker_processes.any?(&:running?)
          @shutdown_status = :initiated_forced
          Process.kill(:TERM, *@worker_processes.select(&:running?).map(&:pid))
        end
      end

      def success?
        @results.success? && !shutting_down?
      end

      def exit_with_status
        Kernel.exit(success? ? 0 : 1)
      end

      def debug(message)
        return unless @verbose

        @formatter.print_debug("[conductor] #{message}")
      end
    end
  end
end
