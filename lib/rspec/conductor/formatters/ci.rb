module RSpec
  module Conductor
    module Formatters
      class CI
        include Conductor::ANSI

        DEFAULT_PRINTOUT_INTERVAL = 10

        # @option printout_interval how often a printout happens, in seconds
        def initialize(printout_interval: DEFAULT_PRINTOUT_INTERVAL)
          @printout_interval = printout_interval
          @last_printout = Time.now
        end

        def handle_worker_message(_worker_process, message, results)
          public_send(message[:type], message) if respond_to?(message[:type])
          print_status(results) if @last_printout + @printout_interval < Time.now
        end

        def print_status(results)
          @last_printout = Time.now
          pct_done = results[:spec_files_total].positive? ? results[:spec_files_processed].to_f / results[:spec_files_total] : 0

          puts "-" * tty_width
          puts "Current status [#{Time.now.strftime("%H:%M:%S")}]:"
          puts "Processed: #{results[:spec_files_processed]} / #{results[:spec_files_total]} (#{(pct_done * 100).floor}%)"
          puts "#{results[:passed]} passed, #{results[:failed]} failed, #{results[:pending]} pending"
          if results[:errors].any?
            puts "Failures:\n"
            results[:errors].each_with_index do |error, i|
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
          puts "-" * tty_width
        end
      end
    end
  end
end
