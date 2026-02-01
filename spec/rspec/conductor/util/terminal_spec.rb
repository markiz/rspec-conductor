# frozen_string_literal: true

require 'spec_helper'

describe RSpec::Conductor::Util::Terminal do
  let(:output) { StringIO.new }
  let(:terminal) { described_class.new(output) }

  describe "#puts" do
    it "creates a non-truncatable line" do
      line = terminal.puts "hello world"
      expect(line.truncate).to be false
    end

    it "writes content to output" do
      terminal.puts "hello world"
      expect(output.string).to eq("\e[2K\rhello world\n")
    end
  end

  describe "#line" do
    it "creates a truncatable line" do
      line = terminal.line "hello world"
      expect(line.truncate).to be true
    end

    it "writes content to output" do
      terminal.line "hello world"
      expect(output.string).to eq("\e[2K\rhello world\n")
    end

    it "truncates content when output is a TTY" do
      allow(terminal).to receive(:tty?).and_return(true)
      allow(terminal).to receive(:tty_width).and_return(5)
      terminal.line "hello world"
      expect(output.string).to eq("\e[2K\rhello\n")
    end

    it "does not truncate content when output is not a TTY" do
      allow(terminal).to receive(:tty?).and_return(false)
      terminal.line "hello world"
      expect(output.string).to eq("\e[2K\rhello world\n")
    end
  end

  describe "Line#update" do
    it "updates the line content" do
      line = terminal.line "initial"
      line.update "updated"
      expect(line.to_s).to eq("updated")
    end

    it "outputs cursor movement and updated content" do
      allow(terminal).to receive(:tty?).and_return(true)

      line = terminal.line "initial"
      line.update "updated"

      # First: clear line + "initial\n", Second: cursor up 1 + clear + "updated\n"
      expect(output.string).to eq("\e[2K\rinitial\n\e[1A\e[2K\rupdated\n")
    end
  end

  describe "complex tests" do
    it "updating lines after the initial print" do
      allow(terminal).to receive(:tty?).and_return(true)
      allow(terminal).to receive(:tty_width).and_return(10)

      line = terminal.puts "a" * 25  # 3 rows at cursor_y=0
      terminal.line "second"         # at cursor_y=3

      # Update: cursor up 4, clear, print short, newline
      line.update "short"

      # First: clear + 25 a's + newline
      # Second: clear + "second" + newline
      # Update: cursor up 4 + clear + "short" + newline
      expect(output.string).to eq(
        "\e[2K\raaaaaaaaaaaaaaaaaaaaaaaaa\n" \
        "\e[2K\rsecond\n" \
        "\e[4A\e[2K\rshort\n"
      )
    end
  end
end
