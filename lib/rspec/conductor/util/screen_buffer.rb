# frozen_string_literal: true

module RSpec
  module Conductor
    module Util
      class ScreenBuffer
        include Util::ANSI

        def initialize(output = $stdout)
          @output = output
          @lines = []
          @cursor_row = 0
          @cursor_col = 0
          @height = 1
        end

        # Accepts new state as an array of strings.
        # Computes the minimal diff and writes ANSI escape sequences to @output.
        def update(new_lines)
          unless @output.tty?
            @output.puts Array(new_lines).map { |line| visible_chars(line) }
            return
          end

          new_lines = Array(new_lines)
          ops = lines_diff(new_lines)
          unless ops.empty?
            @output.print(ops)
            @output.flush
          end
          @lines = new_lines.dup
        end

        def scroll_to_bottom
          @output.print move_cursor(@height, 0, resize_height: false)
        end

        private

        def lines_diff(new_lines)
          buf = +""

          [new_lines.length, @lines.length].max.times do |row|
            old_line = @lines[row] || ""
            new_line = new_lines[row] || ""

            next if old_line == new_line

            old_line_char_groups = split_visible_char_groups(old_line)
            new_line_char_groups = split_visible_char_groups(new_line)
            first_diff_index = new_line_char_groups.size.times.detect { |i| new_line_char_groups[i] != old_line_char_groups[i] } || new_line_char_groups.size

            changed_part = new_line_char_groups[first_diff_index..-1]
            buf << move_cursor(row, first_diff_index)
            buf << changed_part.join
            buf << clear_line_forward if old_line_char_groups.size > new_line_char_groups.size

            @cursor_col = new_line_char_groups.size
          end

          buf
        end

        def move_cursor(row, col, resize_height: true)
          buf = +""

          if row < @cursor_row
            buf << cursor_up(@cursor_row - row)
          elsif row > @cursor_row
            # if our current screen buffer is shorter than the row we want to go to,
            # then we need to output new lines until we reach the right height
            buf << cursor_down([row - @cursor_row, @height - @cursor_row - 1].min)
            newlines = row - @height + 1
            if newlines > 0
              buf << "\n" * newlines
              @cursor_col = 0
            end
          end

          buf << cursor_column(col + 1) if @cursor_col != col
          @height = [@height, row + 1].max if resize_height
          @cursor_row = row
          @cursor_col = col
          buf
        end
      end
    end
  end
end
