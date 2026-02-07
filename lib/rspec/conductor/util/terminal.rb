# frozen_string_literal: true

require_relative "../ansi"
require_relative "screen_buffer"

module RSpec
  module Conductor
    module Util
      class Terminal
        include Conductor::ANSI

        class Line
          attr_reader :content, :truncate

          def initialize(terminal, content, truncate: true)
            @terminal = terminal
            @content = content
            @truncate = truncate
          end

          def update(new_content)
            @content = new_content
            @terminal.redraw
          end

          def to_s
            @content
          end
        end

        def initialize(output = $stdout, screen_buffer = ScreenBuffer.new(output))
          @output = output
          @screen_buffer = screen_buffer
          @lines = []
        end

        def line(content = "", truncate: true)
          Line.new(self, content, truncate: truncate).tap do |new_line|
            @lines << new_line
            redraw
          end
        end

        def puts(content = "")
          line(content, truncate: false)
        end

        def scroll_to_bottom
          @screen_buffer.scroll_to_bottom
        end

        def redraw
          screen_lines = @lines.flat_map { |line| line.truncate ? truncate_to_tty_width(line.content) : rewrap_to_tty_width(line.content) }
          @screen_buffer.update(screen_lines)
        end

        private

        def truncate_to_tty_width(string)
          return string unless tty?

          split_visible_char_groups(string).take(tty_width(@output)).join
        end

        def rewrap_to_tty_width(string)
          return string unless tty?

          split_visible_char_groups(string).each_slice(tty_width(@output)).map(&:join)
        end

        def tty?
          @output.tty?
        end
      end
    end
  end
end
