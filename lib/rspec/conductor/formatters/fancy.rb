# frozen_string_literal: true

require "pathname"

module RSpec
  module Conductor
    module Formatters
      class Fancy
        include Util::ANSI

        def self.recommended?
          $stdout.tty? && $stdout.winsize[0] >= 30 && $stdout.winsize[1] >= 80
        end

        def initialize(worker_count:)
          @worker_processes = {}
          @terminal = Util::Terminal.new
          @last_rendered_lines = []
          @dots_string = +""
          @last_error = nil

          @progress_bar_line = @terminal.line
          @terminal.puts
          @workers_box = @terminal.box
          @worker_lines = worker_count.times.to_h { |i| [i + 1, @workers_box.line] }
          @terminal.puts
          @dots_line = @terminal.line(truncate: false)
          @terminal.puts
          @last_error_line = @terminal.line(truncate: false)
        end

        def handle_worker_message(worker_process, message, results)
          public_send(message[:type], worker_process, message) if respond_to?(message[:type])
          redraw(worker_process, results)
        end

        def example_passed(_worker_process, _message)
          dot ".", :green
        end

        def example_failed(_worker_process, message)
          dot "F", :red
          @last_error = message.slice(:description, :location, :exception_class, :message, :backtrace)
        end

        def example_retried(_worker_process, _message)
          dot "R", :magenta
        end

        def example_pending(_worker_process, _message)
          dot "*", :yellow
        end

        private

        def redraw(worker_process, results)
          update_worker_status_line(worker_process)
          update_results_line(results)
          update_errors_line
          @terminal.scroll_to_bottom
        end

        def dot(text, color)
          @dots_string << colorize(text, color)
          @dots_line.update(@dots_string)
        end

        def update_worker_status_line(worker_process)
          status = colorize("Worker #{worker_process.number}: ", :cyan)
          status << if worker_process.status == :shut_down
                      "(finished)"
                    elsif worker_process.status == :terminated
                      colorize("(terminated)", :red)
                    elsif worker_process.current_spec
                      relative_path(worker_process.current_spec)
                    else
                      "(idle)"
                    end

          @worker_lines[worker_process.number].update(status)
        end

        def update_results_line(results)
          pct = results.spec_file_processed_percentage
          bar_width = [tty_width - 20, 20].max
          filled = (pct * bar_width).floor
          empty = bar_width - filled

          percentage = " %3d%% (%d/%d)" % [(pct * 100).floor, results.spec_files_processed, results.spec_files_total]
          bar = colorize("[", :reset) + colorize("▓", :green) * filled + colorize(" ", :reset) * empty + colorize("]", :reset)

          @progress_bar_line.update(bar + percentage)
        end

        def update_errors_line
          return unless @last_error

          error_components = []
          error_components << colorize("Most recent failure:", :red)
          error_components << "  #{@last_error[:description]}"
          error_components << "  #{@last_error[:location]}"

          if @last_error[:exception_class] || @last_error[:message]
            error_components << "  #{[@last_error[:exception_class], visible_chars(@last_error[:message])].compact.join(": ")}"
          end

          if @last_error[:backtrace]&.any?
            error_components << "  Backtrace:"
            @last_error[:backtrace].first(10).each { |l| error_components << "    #{l}" }
          end

          @last_error_line.update(error_components.join("\n"))
        end

        def relative_path(filename)
          Pathname(filename).relative_path_from(Conductor.root).to_s
        end
      end
    end
  end
end
