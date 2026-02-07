# frozen_string_literal: true

require "spec_helper"

describe RSpec::Conductor::Util::ANSI do
  describe "#colorize" do
    it "allows using a single color" do
      expect(described_class.colorize("hello", :red))
        .to eq("\e[31mhello\e[0m")
    end

    it "allows using multiple colors" do
      expect(described_class.colorize("hello", [:bold, :red]))
        .to eq("\e[1;31mhello\e[0m")
    end

    it "allows setting reset to false" do
      expect(described_class.colorize("hello", :red, reset: false))
        .to eq("\e[31mhello")
    end

    describe "#color_code" do
      it "returns ansi color code" do
        expect(described_class.color_code(:red)).to eq("31")
        expect(described_class.color_code(:red)).to eq("31")
      end
    end

    describe "#cursor_up" do
      it "returns ansi code for lines up" do
        expect(described_class.cursor_up(1)).to eq("\e[1A")
        expect(described_class.cursor_up(7)).to eq("\e[7A")
        expect(described_class.cursor_up(13)).to eq("\e[13A")
      end

      it "returns empty string for non-positive numbers" do
        expect(described_class.cursor_up(-1)).to eq("")
      end
    end

    describe "#cursor_down" do
      it "returns ansi code for lines down" do
        expect(described_class.cursor_down(1)).to eq("\e[1B")
        expect(described_class.cursor_down(7)).to eq("\e[7B")
        expect(described_class.cursor_down(13)).to eq("\e[13B")
      end

      it "returns empty string for non-positive numbers" do
        expect(described_class.cursor_down(-1)).to eq("")
      end
    end

    describe "#clear_line" do
      it "returns a code for ansi line clear" do
        expect(described_class.clear_line).to eq("\e[2K\r")
      end
    end

    describe "#split_visible_char_groups" do
      it "splits a string into visible characters, gluing the color codes to the nearest visible character", :aggregate_failures do
        # <red>h<bold,blue>e<green>llo =>
        # <red>h, <bold,blue>e, <green>l, l, o
        expect(described_class.split_visible_char_groups("\e[31m" + "h" + "\e[1;34m" + "e" + "\e[33m" + "llo"))
          .to eq(["\e[31mh", "\e[1;34me", "\e[33ml", "l", "o"])

        # empty string edgecase
        # <red><blue> =>
        # <red><blue>
        expect(described_class.split_visible_char_groups("\e[31m" + "\e[1;34m"))
          .to eq(["\e[31m\e[1;34m"])

        # multiple tailing codes edgecase
        # <red>h<blue><green>ello =>
        # <red>h, <blue><green>e, l, l, o
        expect(described_class.split_visible_char_groups("\e[31m" + "h" + "\e[34m" + "\e[33m" + "ello"))
          .to eq(["\e[31mh", "\e[34m\e[33me", "l", "l", "o"])

        # multiple leading codes edgecase
        # <red><blue><green>hello =>
        # <red><blue><green>h, e, l, l, o
        expect(described_class.split_visible_char_groups("\e[31m" + "\e[34m" + "\e[33m" + "hello"))
          .to eq(["\e[31m\e[34m\e[33mh", "e", "l", "l", "o"])
      end
    end

    describe "#visible_chars" do
      it "strips all ansi codes" do
        # <cursor up 2 lines><bold, red>hello<reset> => hello
        expect(described_class.visible_chars("\e[2A\e[1;31mhello\e[0m")).to eq("hello")
      end
    end

    describe "#tty_width" do
      it "returns some number" do
        expect(described_class.tty_width).to be > 0
      end
    end
  end
end
