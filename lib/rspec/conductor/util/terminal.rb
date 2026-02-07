# frozen_string_literal: true

require_relative "screen_buffer"

module RSpec
  module Conductor
    module Util
      class Terminal
        include Util::ANSI

        class Line
          attr_reader :content, :truncate

          def initialize(terminal, content, truncate: true)
            @terminal = terminal
            @truncate = truncate
            yield self if block_given?
            update(content)
          end

          def update(new_content)
            @content = new_content
            @terminal.redraw
          end

          def to_s
            @content
          end

          def lines
            [self]
          end
        end

        class Box
          attr_reader :lines

          def initialize(terminal)
            @terminal = terminal
            @lines = []
            yield self if block_given?
          end

          def line(content = "", truncate: true)
            Line.new(@terminal, content, truncate: truncate) { |l| @lines << l }
          end

          def puts(content = "")
            Line.new(@terminal, content, truncate: false) { |l| @lines << l }
          end
        end

        def initialize(output = $stdout, screen_buffer = ScreenBuffer.new(output))
          @output = output
          @screen_buffer = screen_buffer
          @elements = []
        end

        def line(content = "", truncate: true)
          Line.new(self, content, truncate: truncate) { |l| @elements << l }
        end

        def puts(content = "")
          line(content, truncate: false)
        end

        def box
          Box.new(self) { |b| @elements << b }
        end

        def scroll_to_bottom
          @screen_buffer.scroll_to_bottom
        end

        def redraw
          screen_lines = @elements.flat_map(&:lines).flat_map { |line| line.truncate ? truncate_to_tty_width(line.content) : rewrap_to_tty_width(line.content) }
          @screen_buffer.update(screen_lines.take(tty_height(@output) - 1))
        end

        private

        def truncate_to_tty_width(string)
          return string unless tty?

          split_visible_char_groups(string).take(tty_width(@output)).join
        end

        def rewrap_to_tty_width(string)
          return string unless tty?

          string.split("\n").flat_map do |line|
            _, indent, body = line.partition(/^\s*/)
            max_width = tty_width(@output) - indent.size
            split_visible_char_groups(body).each_slice(max_width).map { |chars| "#{indent}#{chars.join}" }
          end
        end

        def tty?
          @output.tty?
        end
      end
    end
  end
end
