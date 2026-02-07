# frozen_string_literal: true

require_relative "screen_buffer"

module RSpec
  module Conductor
    module Util
      class Terminal
        include Util::ANSI

        INDENTATION_REGEX = /^(\s+)(.*)$/

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
          def initialize(terminal)
            @terminal = terminal
            @contents = []
            yield self if block_given?
          end

          def line(content = "", truncate: true)
            Line.new(@terminal, content, truncate: truncate) { |l| @contents << l }
          end

          def puts(content = "")
            Line.new(@terminal, content, truncate: false) { |l| @contents << l }
          end

          def box
            Box.new(@terminal) { |b| @contents << b }
          end

          def lines
            @contents.flat_map(&:lines)
          end
        end

        def initialize(output = $stdout, screen_buffer = ScreenBuffer.new(output))
          @output = output
          @screen_buffer = screen_buffer
          @wrapper_box = Box.new(self)
        end

        def line(content = "", truncate: true)
          @wrapper_box.line(content, truncate: truncate)
        end

        def puts(content = "")
          @wrapper_box.puts(content)
        end

        def box
          @wrapper_box.box
        end

        def scroll_to_bottom
          @screen_buffer.scroll_to_bottom
        end

        def redraw
          screen_lines = @wrapper_box.lines.flat_map { |line| line.truncate ? truncate_to_tty_width(line.content) : rewrap_to_tty_width(line.content) }
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
            indent, body = line.match(INDENTATION_REGEX)&.captures || ["", line]
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
