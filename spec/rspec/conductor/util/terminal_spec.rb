# frozen_string_literal: true

require "spec_helper"

describe RSpec::Conductor::Util::Terminal do
  let(:output) { StringIO.new }
  let(:tty) { true }
  let(:tty_width) { 80 }
  let(:tty_height) { 25 }
  let(:screen_buffer) { spy("ScreenBuffer") }
  let(:terminal) { described_class.new(output, screen_buffer) }

  before do
    allow(output).to receive(:tty?).and_return(tty)
    allow(output).to receive(:winsize).and_return([tty_height, tty_width])
  end

  describe "#puts" do
    it "creates a non-truncatable line" do
      line = terminal.puts "hello world"
      expect(line.truncate).to be false
    end

    it "writes content to the screen buffer" do
      terminal.puts "hello"
      expect(screen_buffer).to have_received(:update).with(["hello"])

      terminal.puts "world"
      expect(screen_buffer).to have_received(:update).with(["hello", "world"])
    end

    it "allows updating a line" do
      line = terminal.puts "hello"
      expect(screen_buffer).to have_received(:update).with(["hello"])
      line.update("hello world")
      expect(screen_buffer).to have_received(:update).with(["hello world"])
    end

    it "translates longer lines into multiple screen lines for the buffer" do
      terminal.puts "A" * tty_width
      expect(screen_buffer).to have_received(:update).with(["A" * tty_width])
      terminal.puts "B" * (tty_width + 1)
      expect(screen_buffer).to have_received(:update).with(["A" * tty_width, "B" * tty_width, "B"])
    end
  end

  describe "#line" do
    it "creates a truncatable line" do
      line = terminal.line "hello world"
      expect(line.truncate).to be true
    end

    it "writes content to the screen buffer" do
      terminal.line "hello"
      expect(screen_buffer).to have_received(:update).with(["hello"])

      terminal.line "world"
      expect(screen_buffer).to have_received(:update).with(["hello", "world"])
    end

    it "allows updating a line" do
      line = terminal.line "hello"
      expect(screen_buffer).to have_received(:update).with(["hello"])
      line.update("hello world")
      expect(screen_buffer).to have_received(:update).with(["hello world"])
    end

    it "truncates longer lines" do
      terminal.line "A" * tty_width
      expect(screen_buffer).to have_received(:update).with(["A" * tty_width])
      terminal.line "B" * (tty_width + 1)
      expect(screen_buffer).to have_received(:update).with(["A" * tty_width, "B" * tty_width])
    end
  end

  describe "#redraw" do
    it "calls screen_buffer#update" do
      terminal.redraw
      expect(screen_buffer).to have_received(:update).with([])
    end
  end

  describe "#scroll_to_bottom" do
    it "calls screen_buffer#scroll_to_bottom" do
      terminal.scroll_to_bottom
      expect(screen_buffer).to have_received(:scroll_to_bottom)
    end
  end
end
