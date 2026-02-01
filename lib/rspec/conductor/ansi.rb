# frozen_string_literal: true

require "io/console"

module RSpec
  module Conductor
    module ANSI
      module_function

      COLOR_CODES = {
        # Reset
        reset: "0",

        # Styles
        bold: "1",
        dim: "2",
        italic: "3",
        underline: "4",
        blink: "5",
        inverse: "7",
        hidden: "8",
        strikethrough: "9",

        # Foreground colors
        black: "30",
        red: "31",
        green: "32",
        yellow: "33",
        blue: "34",
        magenta: "35",
        cyan: "36",
        white: "37",

        # Bright foreground colors
        bright_black: "90",
        bright_red: "91",
        bright_green: "92",
        bright_yellow: "93",
        bright_blue: "94",
        bright_magenta: "95",
        bright_cyan: "96",
        bright_white: "97",

        # Background colors
        bg_black: "40",
        bg_red: "41",
        bg_green: "42",
        bg_yellow: "43",
        bg_blue: "44",
        bg_magenta: "45",
        bg_cyan: "46",
        bg_white: "47",

        # Bright background colors
        bg_bright_black: "100",
        bg_bright_red: "101",
        bg_bright_green: "102",
        bg_bright_yellow: "103",
        bg_bright_blue: "104",
        bg_bright_magenta: "105",
        bg_bright_cyan: "106",
        bg_bright_white: "107",
      }.freeze

      def colorize(string, colors, reset: true)
        [
          "\e[",
          Array(colors).map { |color| color_code(color) }.join(";"),
          "m",
          string,
          reset ? "\e[#{color_code(:reset)}m" : nil,
        ].join
      end

      def color_code(color)
        COLOR_CODES.fetch(color, COLOR_CODES[:reset])
      end

      def cursor_up(n_lines)
        n_lines.positive? ? "\e[#{n_lines}A" : ""
      end

      def cursor_down(n_lines)
        n_lines.positive? ? "\e[#{n_lines}B" : ""
      end

      def clear_line
        "\e[2K\r"
      end

      # sticks invisible characters to visible ones when splitting (so that an ansi color code doesn"t get split mid-way)
      def split_visible_char_groups(string)
        invisible = "(?:\\e\\[[0-9;]*[a-zA-Z])"
        visible = "(?:[^\\e])"
        scan_regex = Regexp.new("#{invisible}*#{visible}#{invisible}*|#{invisible}+")
        string.scan(scan_regex)
      end

      def visible_chars(string)
        string.gsub(/\e\[[0-9;]*[a-zA-Z]/, '')
      end

      def tty_width(tty = $stdout)
        return 80 unless tty.tty?

        tty.winsize[1]
      end
    end
  end
end
