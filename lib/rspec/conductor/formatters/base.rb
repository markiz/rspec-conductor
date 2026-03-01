# frozen_string_literal: true

module RSpec
  module Conductor
    class Base
      include Util::ANSI

      def initialize(**_kwargs)
      end

      def handle_worker_message(_worker_process, _message, _results)
      end

      def print_startup_banner(worker_count:, seed:, spec_files_count:)
        puts "RSpec Conductor starting with #{worker_count} workers (seed: #{seed})"
        puts "Running #{spec_files_count} spec files\n\n"
      end

      def print_summary(results, seed:)
        puts "\n\n"
        puts "Randomized with seed #{seed}"
        puts "#{colorize("#{results.passed} passed", :green)}, #{colorize("#{results.failed} failed", :red)}, #{colorize("#{results.pending} pending", :yellow)}"
        puts colorize("Worker crashes: #{results.worker_crashes}", :red) if results.worker_crashes.positive?

        if results.errors.any?
          puts "\nFailures:\n\n"
          results.errors.each_with_index do |error, i|
            puts "  #{i + 1}) #{error[:description]}"
            puts colorize("     #{error[:message]}", :red) if error[:message]
            puts colorize("     #{error[:location]}", :cyan)
            if error[:backtrace]&.any?
              puts "     Backtrace:"
              error[:backtrace].each { |line| puts "       #{line}" }
            end
            puts
          end
        end

        puts "Specs took: #{results.specs_runtime.round(2)}s"
        puts "Total runtime: #{results.total_runtime.round(2)}s"
        puts "Suite: #{results.success? ? colorize("PASSED", :green) : colorize("FAILED", :red)}"
      end

      def handle_worker_stdout(worker_number, string)
        puts "[worker #{worker_number}] #{string}"
      end

      def handle_worker_stderr(worker_number, string)
        $stderr.puts "[worker #{worker_number}] #{string}"
      end

      def print_debug(string)
        $stderr.puts string
      end

      def print_retry_message(message)
        puts <<~EOM
          \nRetried: #{message[:description]}
            #{message[:location]}
            #{message[:exception_class]}: #{message[:message]}
            Backtrace:
          #{message[:backtrace].map { "    #{_1}" }.join("\n")}
        EOM
      end

      def print_shut_down_banner
        puts "Shutting down... (press ctrl-c again to force quit)"
      end

      def colorize(string, colors, **kwargs)
        $stdout.tty? ? super(string, colors, **kwargs) : string
      end
    end
  end
end
