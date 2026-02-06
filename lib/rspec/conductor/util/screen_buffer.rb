# frozen_string_literal: true

require_relative "../ansi"

module RSpec
  module Conductor
    module Util
      class ScreenBuffer
        include Conductor::ANSI

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
          new_lines = Array(new_lines)
          ops = lines_diff(new_lines)

          @lines = new_lines.map(&:dup)
          unless ops.empty?
            @output.print(ops)
            @output.flush
          end

          ops
        end

        def scroll_to_bottom
          @output.print move_cursor(@height, 0)
        end

        private

        def lines_diff(new_lines)
          buf = String.new(encoding: Encoding.default_external)

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

            move_cursor(row, new_line_char_groups.size)
          end

          buf
        end

        def move_cursor(row, col)
          buf = String.new(encoding: Encoding.default_external)

          if row < @cursor_row
            buf << cursor_up(@cursor_row - row)
          elsif row > @cursor_row
            # if our current screen buffer is shorter than the row we want to go to,
            # then we need to output new lines until we reach the right height
            buf << cursor_down([row - @cursor_row, @height - @cursor_row - 1].min)
            buf << "\n" * [row - (@height - 1), 0].max
          end

          buf << cursor_column(col + 1)
          @height = [@height, row + 1].max
          @cursor_row = row
          @cursor_col = col
          buf
        end
      end
    end
  end
end
