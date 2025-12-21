require "pathname"

module RSpec
  module Conductor
    module Formatters
      class Fancy
        RED = 31
        GREEN = 32
        YELLOW = 33
        MAGENTA = 35
        CYAN = 36
        NORMAL = 0

        def self.recommended?
          $stdout.tty? && $stdout.winsize[0] >= 60 && $stdout.winsize[1] >= 80
        end

        def initialize
          @workers = Hash.new { |h, k| h[k] = {} }
          @last_rendered_lines = []
          @dots = []
          @last_error = nil
        end

        def handle_worker_message(worker, message, results)
          @workers[worker[:number]] = worker
          public_send(message[:type], worker, message) if respond_to?(message[:type])
          redraw(results)
        end

        def example_passed(_worker, _message)
          @dots << { char: ".", color: GREEN }
        end

        def example_failed(_worker, message)
          @dots << { char: "F", color: RED }
          @last_error = message.slice(:description, :location, :exception_class, :message, :backtrace)
        end

        def example_retried(_worker, _message)
          @dots << { char: "R", color: MAGENTA }
        end

        def example_pending(_worker, _message)
          @dots << { char: "*", color: YELLOW }
        end

        private

        def redraw(results)
          cursor_up(rewrap_lines(@last_rendered_lines).length)

          lines = []
          lines << progress_bar(results)
          lines << ""
          lines.concat(worker_lines)
          lines << ""
          lines << @dots.map { colorize(_1[:char], _1[:color]) }.join
          lines << ""
          lines.concat(error_lines) if @last_error
          lines = rewrap_lines(lines)

          lines.each_with_index do |line, i|
            if @last_rendered_lines[i] == line
              cursor_down(1)
            else
              clear_line
              puts line
            end
          end

          if @last_rendered_lines.length && lines.length < @last_rendered_lines.length
            (@last_rendered_lines.length - lines.length).times do
              clear_line
              puts
            end
            cursor_up(@last_rendered_lines.length - lines.length)
          end

          @last_rendered_lines = lines
        end

        def worker_lines
          return [] unless max_worker_num.positive?

          (1..max_worker_num).map do |num|
            worker = @workers[num]
            prefix = colorize("Worker #{num}: ", CYAN)

            if worker[:status] == :shut_down
              prefix + "(finished)"
            elsif worker[:status] == :terminated
              prefix + colorize("(terminated)", RED)
            elsif worker[:current_spec]
              prefix + truncate(relative_path(worker[:current_spec]), tty_width - 15)
            else
              prefix + "(idle)"
            end
          end
        end

        def error_lines
          return [] unless @last_error

          lines = []
          lines << colorize("Most recent failure:", RED)
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
            split_chars_respecting_ansi(body).each_slice(max_width).map { "#{indent}#{_1.join}" }
          end
        end

        # sticks invisible characters to visible ones when splitting (so that an ansi color code doesn"t get split mid-way)
        def split_chars_respecting_ansi(body)
          invisible = "(?:\\e\\[[\\d;]*m)"
          visible = "(?:[^\\e])"
          scan_regex = Regexp.new("#{invisible}*#{visible}#{invisible}*|#{invisible}+")
          body.scan(scan_regex)
        end

        def progress_bar(results)
          total = results[:spec_files_total]
          processed = results[:spec_files_processed]
          pct = total.positive? ? processed.to_f / total : 0
          bar_width = [tty_width - 60, 20].max

          filled = (pct * bar_width).floor
          empty = bar_width - filled

          bar = colorize("[", NORMAL) + colorize("▓" * filled, GREEN) + colorize(" " * empty, NORMAL) + colorize("]", NORMAL)
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

        def colorize(string, color)
          $stdout.tty? ? "\e[#{color}m#{string}\e[#{NORMAL}m" : string
        end

        def cursor_up(n_lines)
          print("\e[#{n_lines}A") if $stdout.tty? && n_lines.positive?
        end

        def cursor_down(n_lines)
          print("\e[#{n_lines}B") if $stdout.tty? && n_lines.positive?
        end

        def clear_line
          print("\e[2K\r") if $stdout.tty?
        end

        def tty_width
          $stdout.tty? ? $stdout.winsize[1] : 80
        end
      end
    end
  end
end
