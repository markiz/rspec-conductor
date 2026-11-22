# frozen_string_literal: true

module RSpec
  module Conductor
    module Formatters
      class CI < Base
        DEFAULT_PRINTOUT_INTERVAL = 10

        # @option printout_interval how often a printout happens, in seconds
        def initialize(printout_interval: DEFAULT_PRINTOUT_INTERVAL, **kwargs)
          @printout_interval = printout_interval
          @last_printout = Time.now

          super(**kwargs)
        end

        def handle_worker_message(_worker_process, message, suite_run)
          public_send(message[:type], message) if respond_to?(message[:type])
          print_status(suite_run) if @last_printout + @printout_interval < Time.now
        end

        def print_status(suite_run)
          @last_printout = Time.now
          pct = suite_run.spec_file_processed_percentage

          puts "-" * tty_width
          puts "Current status [#{Time.now.strftime("%H:%M:%S")}]:"
          puts "Processed: #{suite_run.spec_files_processed} / #{suite_run.spec_files_total} (#{(pct * 100).floor}%)"
          puts "#{suite_run.examples_passed} passed, #{suite_run.examples_failed} failed, #{suite_run.examples_pending} pending"
          if suite_run.errors.any?
            puts "Failures:\n"
            suite_run.errors.each_with_index do |error, i|
              puts "  #{i + 1}) #{error[:description]}"
              puts "     #{error[:location]}" if error[:location]
              puts "     #{error[:message]}" if error[:message]
              if error[:backtrace]&.any?
                puts "     Backtrace:"
                error[:backtrace].each { |line| puts "       #{line}" }
              end
              puts
            end
          end
          puts "-" * tty_width
        end
      end
    end
  end
end
