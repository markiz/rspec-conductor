require "pathname"

module RSpec
  module Conductor
    module Formatters
      class Fancy
        include Conductor::ANSI

        def self.recommended?
          $stdout.tty? && $stdout.winsize[0] >= 30 && $stdout.winsize[1] >= 80
        end

        def initialize
          @workers = Hash.new { |h, k| h[k] = {} }
          @last_rendered_lines = []
          @dots = []
          @last_error = nil
        end

        def handle_worker_message(worker, message, results)
          @workers[worker.number] = worker
          public_send(message[:type], worker, message) if respond_to?(message[:type])
          redraw(results)
        end

        def example_passed(_worker, _message)
          @dots << { char: ".", color: :green }
        end

        def example_failed(_worker, message)
          @dots << { char: "F", color: :red }
          @last_error = message.slice(:description, :location, :exception_class, :message, :backtrace)
        end

        def example_retried(_worker, _message)
          @dots << { char: "R", color: :magenta }
        end

        def example_pending(_worker, _message)
          @dots << { char: "*", color: :yellow }
        end

        private

        def redraw(results)
          print_cursor_up(rewrap_lines(@last_rendered_lines).length)

          lines = []
          lines << progress_bar(results)
          lines << ""
          lines.concat(worker_lines)
          lines << ""
          lines << @dots.map { |dot| colorize(dot[:char], dot[:color]) }.join
          lines << ""
          lines.concat(error_lines) if @last_error
          lines = rewrap_lines(lines)

          lines.each_with_index do |line, i|
            if @last_rendered_lines[i] == line
              print_cursor_down(1)
            else
              print_clear_line
              puts line
            end
          end

          if @last_rendered_lines.length && lines.length < @last_rendered_lines.length
            (@last_rendered_lines.length - lines.length).times do
              print_clear_line
              puts
            end
            print_cursor_up(@last_rendered_lines.length - lines.length)
          end

          @last_rendered_lines = lines
        end

        def worker_lines
          return [] unless max_worker_num.positive?

          (1..max_worker_num).map do |num|
            worker = @workers[num]
            prefix = colorize("Worker #{num}: ", :cyan)

            if worker.status == :shut_down
              prefix + "(finished)"
            elsif worker.status == :terminated
              prefix + colorize("(terminated)", :red)
            elsif worker.current_spec
              prefix + truncate(relative_path(worker.current_spec), tty_width - 15)
            else
              prefix + "(idle)"
            end
          end
        end

        def error_lines
          return [] unless @last_error

          lines = []
          lines << colorize("Most recent failure:", :red)
          lines << "  #{@last_error[:description]}"
          lines << "  #{@last_error[:location]}"

          if @last_error[:exception_class] || @last_error[:message]
            err_msg = [@last_error[:exception_class], @last_error[:message]].compact.join(": ")
            lines << "  #{err_msg}"
          end

          if @last_error[:backtrace]&.any?
            lines << "  Backtrace:"
            @last_error[:backtrace].first(10).each { |l| lines << "    #{l}" }
          end

          lines
        end

        def rewrap_lines(lines)
          lines.flat_map do |line|
            _, indent, body = line.partition(/^\s*/)
            max_width = tty_width - indent.size
            split_visible_char_groups(body).each_slice(max_width).map { |chars| "#{indent}#{chars.join}" }
          end
        end

        def progress_bar(results)
          total = results[:spec_files_total]
          processed = results[:spec_files_processed]
          pct = total.positive? ? processed.to_f / total : 0
          bar_width = [tty_width - 20, 20].max

          filled = (pct * bar_width).floor
          empty = bar_width - filled

          bar = colorize("[", :reset) + colorize("▓" * filled, :green) + colorize(" " * empty, :reset) + colorize("]", :reset)
          percentage = " #{(pct * 100).floor.to_s.rjust(3)}% (#{processed}/#{total})"

          bar + percentage
        end

        def max_worker_num
          @workers.keys.max || 0
        end

        def relative_path(filename)
          Pathname(filename).relative_path_from(Conductor.root).to_s
        end

        def truncate(str, max_length)
          return "" unless str

          str.length > max_length ? "...#{str[-(max_length - 3)..]}" : str
        end

        def print_cursor_up(n_lines)
          print cursor_up(n_lines) if $stdout.tty?
        end

        def print_cursor_down(n_lines)
          print cursor_down(n_lines) if $stdout.tty?
        end

        def print_clear_line
          print clear_line if $stdout.tty?
        end
      end
    end
  end
end
