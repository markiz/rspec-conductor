# frozen_string_literal: true

module RSpec
  module Conductor
    module Formatters
      class Base
        include Util::ANSI

        def initialize(**_kwargs)
        end

        def handle_worker_message(_worker_process, _message, _suite_run)
        end

        def print_startup_banner(worker_count:, seed:, spec_files_count:)
          puts "RSpec Conductor starting with #{worker_count} workers (seed: #{seed})"
          puts "Running #{spec_files_count} spec files\n\n"
        end

        def print_summary(suite_run, seed:, success:)
          puts "\n\n"
          puts "Randomized with seed #{seed}"
          puts "#{colorize("#{suite_run.examples_passed} passed", :green)}, #{colorize("#{suite_run.examples_failed} failed", :red)}, #{colorize("#{suite_run.examples_pending} pending", :yellow)}"
          puts colorize("Worker crashes: #{suite_run.worker_crashes}", :red) if suite_run.worker_crashes.positive?

          if suite_run.errors.any?
            puts "\nFailures:\n\n"
            suite_run.errors.each_with_index do |error, i|
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

          puts "Specs took: #{suite_run.specs_runtime.round(2)}s"
          puts "Total runtime: #{suite_run.total_runtime.round(2)}s"
          puts "Suite: #{success ? colorize("PASSED", :green) : colorize("FAILED", :red)}"

          if suite_run.errors.any?
            puts ""
            puts "To rerun failed examples:"
            puts "  rspec #{suite_run.errors.map { |e| e[:location] }.join(" ")}"
          end
        end

        def print_slowest(suite_run, n)
          puts "\n\n"
          puts "Slowest #{n} specs:"
          suite_run.example_stats.sort_by { |e| -e[:run_time] }.take(n).each_with_index do |e, i|
            puts "%3d. (%8.2fms) %s @ %s" % [i + 1, e[:run_time] * 1000, colorize(e[:description], :dim), colorize(e[:location], :cyan)]
          end
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

        def print_shutdown_banner
          puts "Shutting down... (press ctrl-c again to force quit)"
        end

        def colorize(string, colors, **kwargs)
          $stdout.tty? ? super(string, colors, **kwargs) : string
        end
      end
    end
  end
end
