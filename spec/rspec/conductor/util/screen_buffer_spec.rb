# frozen_string_literal: true

require "spec_helper"

describe RSpec::Conductor::Util::ScreenBuffer do
  let(:output) { StringIO.new }
  let(:screen_buffer) { described_class.new(output) }

  describe "#update" do
    it "accepts the new state and returns a string of chars and codes" do
      screen_buffer.update(["hello"])
      expect(output.string).to eq("hello")
    end

    it "allows multi-line updates" do
      screen_buffer.update(["hello", "world"])
      expect(output.string).to eq("hello\nworld")
    end

    it "allows changing existing outputs" do
      screen_buffer.update(["hello"])
      screen_buffer.update(["help"])
      expect(output.string).to eq("hello\e[4Gp\e[K")
    end

    it "allows changing existing outputs in multi-line" do
      screen_buffer.update(["hello", "world", "third line"])
      expect(output.string).to eq("hello\nworld\nthird line")

      output.rewind
      output.truncate(0)
      screen_buffer.update(["help", "world", "third line"])
      expect(output.string).to eq("\e[2A\e[4Gp\e[K")

      output.rewind
      output.truncate(0)
      screen_buffer.update(["help", "world", "third line 333"])
      expect(output.string).to eq("\e[2B\e[11G 333")
    end
  end

  describe "#scroll_to_bottom" do
    it "scrolls down to the last character, creating a new line if needed" do
      screen_buffer.update(["hello", "world", "third line"])
      screen_buffer.update(["hello 1", "world", "third line"])
      output.rewind
      output.truncate(0)

      screen_buffer.scroll_to_bottom
      expect(output.string).to eq("\e[2B\n")
    end

    it "avoids extending the buffer height when called multiple times" do
      screen_buffer.update(["hello world"])
      output.rewind
      output.truncate(0)
      screen_buffer.scroll_to_bottom
      screen_buffer.scroll_to_bottom
      screen_buffer.scroll_to_bottom
      expect(output.string).to eq("\n")
    end
  end
end
