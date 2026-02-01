# frozen_string_literal: true

require_relative "../ansi"

module RSpec
  module Conductor
    module Util
      class Terminal
        include Conductor::ANSI

        class Line
          attr_reader :cursor_y, :content, :truncate

          def initialize(terminal, content, cursor_y, truncate: true)
            @terminal = terminal
            @cursor_y = cursor_y
            @content = content
            @truncate = truncate
          end

          def update(new_content)
            @content = new_content
            @terminal.redraw_line(self)
          end

          def to_s
            @content
          end
        end

        def initialize(output = $stdout)
          @output = output
          @lines = []
          @cursor_y = 0
          @height = 0
        end

        def puts(content = "")
          create_line(content, truncate: false)
        end

        def line(content = "")
          create_line(content, truncate: true)
        end

        def scroll_to_bottom
          move_cursor_to(@height)
        end

        def redraw
          @lines.each { |line| redraw_line(line) }
        end

        def redraw_line(line)
          move_cursor_to(line.cursor_y)
          render_line(line)
        end

        private

        def create_line(content, truncate:)
          Line.new(self, content.to_s, @height, truncate: truncate).tap do |line|
            @height += truncate ? 1 : tty_lines_count(content)
            @lines << line
            redraw_line(line)
          end
        end

        def render_line(line)
          tty_puts line.content, truncate: line.truncate
        end

        def tty_puts(string, truncate: false)
          string = truncate_to_tty_width(string) if truncate

          @cursor_y += tty_lines_count(string)
          @output.puts "#{clear_line}#{string}"
          @output.flush unless tty?
        end

        def move_cursor_to(cursor_y)
          return unless tty?

          if @cursor_y > cursor_y
            @output.print cursor_up(@cursor_y - cursor_y)
          else
            @output.print cursor_down(cursor_y - @cursor_y)
          end
          @cursor_y = cursor_y
        end

        def tty_lines_count(string)
          # e.g. tty width = 80
          # a 0 char string is 1 line
          # a 79 char string is 1 line
          # a 80 char string is 1 line
          # a 81 char string is 2 lines
          length = [visible_chars(string).length - 1, 0].max
          (length / tty_width(@output)) + 1
        end

        def truncate_to_tty_width(string)
          return string unless tty?

          split_visible_char_groups(string).take(tty_width(@output)).join
        end

        def tty?
          @output.tty?
        end
      end
    end
  end
end
