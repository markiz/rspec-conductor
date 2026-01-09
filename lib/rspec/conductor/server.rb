# frozen_string_literal: true

require "English"
require "socket"
require "json"
require "io/console"

module RSpec
  module Conductor
    class Server
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
        @seed = opts[:seed] || (Random.new_seed % 65_536)
        @fail_fast_after = opts[:fail_fast_after]
        @display_retry_backtraces = opts.fetch(:display_retry_backtraces, false)
        @verbose = opts.fetch(:verbose, false)

        @rspec_args = rspec_args
        @workers = {}
        @spec_queue = []
        @started_at = Time.now
        @shutting_down = false
        @formatter = case opts[:formatter]
                     when "ci"
                       Formatters::CI.new
                     when "fancy"
                       Formatters::Fancy.new
                     when "plain"
                       Formatters::Plain.new
                     else
                       (!@verbose && Formatters::Fancy.recommended?) ? Formatters::Fancy.new : Formatters::Plain.new
                     end
        @results = { passed: 0, failed: 0, pending: 0, errors: [], worker_crashes: 0, started_at: @started_at, spec_files_total: 0, spec_files_processed: 0 }
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

        @results[:success] = @results[:failed].zero? && @results[:errors].empty? && @results[:worker_crashes].zero? && !@shutting_down
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
            @workers.any? ? initiate_shutdown : Kernel.exit(1)
          end
        end
      end

      def initiate_shutdown
        return if @shutting_down

        @shutting_down = true

        puts "Shutting down..."
        @workers.each_value { |w| w[:socket]&.send_message({ type: :shutdown }) }
      end

      def build_spec_queue
        paths = extract_paths_from_args

        config = RSpec::Core::Configuration.new
        config.files_or_directories_to_run = paths

        @spec_queue = config.files_to_run.shuffle(random: Random.new(@seed))
        @results[:spec_files_total] = @spec_queue.size
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

        @workers[pid] = {
          pid: pid,
          number: worker_number,
          status: :running,
          socket: Protocol::Socket.new(parent_socket),
          current_spec: nil,
        }
        assign_work(@workers[pid])
      end

      def run_event_loop
        until @workers.empty?
          workers_by_io = @workers.values.to_h { |w| [w[:socket].io, w] }
          readable_ios, = IO.select(workers_by_io.keys, nil, nil, 0.01)

          readable_ios&.each do |io|
            worker = workers_by_io.fetch(io)
            handle_worker_message(worker)
          end

          reap_workers
        end
      end

      def handle_worker_message(worker)
        message = worker[:socket].receive_message
        return unless message

        debug "Worker #{worker[:number]}: #{message[:type]}"

        case message[:type].to_sym
        when :example_passed
          @results[:passed] += 1
        when :example_failed
          @results[:failed] += 1
          @results[:errors] << message

          if @fail_fast_after && @results[:failed] >= @fail_fast_after && !@shutting_down
            debug "Shutting after #{@results[:failed]} failures"
            initiate_shutdown
          end
        when :example_pending
          @results[:pending] += 1
        when :example_retried
          if @display_retry_backtraces
            puts "\nExample #{message[:description]} retried:\n  #{message[:location]}\n  #{message[:exception_class]}: #{message[:message]}\n#{message[:backtrace].map { "    #{_1}" }.join("\n")}\n"
          end
        when :spec_complete
          @results[:spec_files_processed] += 1
          worker[:current_spec] = nil
          assign_work(worker)
        when :spec_error
          @results[:errors] << message
          debug "Spec error details: #{message[:error]}"
          worker[:current_spec] = nil
          assign_work(worker)
        when :spec_interrupted
          debug "Spec interrupted: #{message[:file]}"
          worker[:current_spec] = nil
        end
        @formatter.handle_worker_message(worker, message, @results)
      end

      def assign_work(worker)
        if @spec_queue.empty? || @shutting_down
          debug "No more work for worker #{worker[:number]}, sending shutdown"
          worker[:socket].send_message({ type: :shutdown })
          cleanup_worker(worker)
        else
          @specs_started_at ||= Time.now
          spec_file = @spec_queue.shift
          worker[:current_spec] = spec_file
          debug "Assigning #{spec_file} to worker #{worker[:number]}"
          message = { type: :worker_assigned_spec, file: spec_file }
          worker[:socket].send_message(message)
          @formatter.handle_worker_message(worker, message, @results)
        end
      end

      def cleanup_worker(worker, status: :shut_down)
        @workers.delete(worker[:pid])
        worker[:socket].close
        worker[:status] = status
        @formatter.handle_worker_message(worker, { type: :worker_shut_down }, @results)
        Process.wait(worker[:pid])
      rescue Errno::ECHILD
        nil
      end

      def reap_workers
        dead_workers = @workers.each_with_object([]) do |(pid, worker), memo|
          result = Process.waitpid(pid, Process::WNOHANG)
          memo << [worker, $CHILD_STATUS] if result
        end

        dead_workers.each do |worker, exitstatus|
          cleanup_worker(worker, status: :terminated)
          @results[:worker_crashes] += 1
          debug "Worker #{worker[:number]} exited with status #{exitstatus.exitstatus}, signal #{exitstatus.termsig}"
        end
      rescue Errno::ECHILD
        nil
      end

      def print_summary
        puts "\n\n"
        puts "=" * ($stdout.tty? ? $stdout.winsize[1] : 80)
        puts "Randomized with seed #{@seed}"
        puts "Results: #{colorize("#{@results[:passed]} passed", :green)}, #{ANSI.colorize("#{@results[:failed]} failed", :red)}, #{ANSI.colorize("#{@results[:pending]} pending", :yellow)}"
        puts colorize("Worker crashes: #{@results[:worker_crashes]}", :red) if @results[:worker_crashes].positive?

        if @results[:errors].any?
          puts "\nFailures:\n\n"
          @results[:errors].each_with_index do |error, i|
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

        puts "Specs took: #{(Time.now - (@specs_started_at || @started_at)).to_f.round(2)}s"
        puts "Total runtime: #{(Time.now - @started_at).to_f.round(2)}s"
        puts "Status: #{@results[:success] ? colorize("PASSED", :green) : colorize("FAILED", :red)}"
      end

      def colorize(string, color)
        $stdout.tty? ? ANSI.colorize(string, color) : string
      end

      def exit_with_status
        Kernel.exit(@results[:success] ? 0 : 1)
      end

      def debug(message)
        return unless @verbose

        $stderr.puts "[conductor] #{message}"
      end
    end
  end
end
