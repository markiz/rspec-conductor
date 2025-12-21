# frozen_string_literal: true

require "spec_helper"

describe RSpec::Conductor::Protocol::Socket do
  before do
    @server_io, @client_io = Socket.pair(:UNIX, :STREAM, 0)
  end

  after do
    @server_io&.close unless @server_io&.closed?
    @client_io&.close unless @client_io&.closed?
  end

  let(:server_socket) { described_class.new(@server_io) }
  let(:client_socket) { described_class.new(@client_io) }

  describe "#send_message and #receive_message" do
    it "sends and receives a simple hash" do
      client_socket.send_message({ type: "hello", data: "world" })
      message = server_socket.receive_message

      expect(message).to eq({ type: "hello", data: "world" })
    end

    it "sends and receives messages with symbolized keys" do
      client_socket.send_message({ "string_key" => "value" })
      message = server_socket.receive_message

      expect(message).to eq({ string_key: "value" })
    end

    it "handles nested data structures" do
      payload = {
        type: "spec_complete",
        results: {
          passed: 10,
          failed: 2,
          errors: [{ file: "spec/foo_spec.rb", line: 42 }]
        }
      }

      client_socket.send_message(payload)
      message = server_socket.receive_message

      expect(message).to eq(payload)
    end

    it "handles multiple sequential messages" do
      client_socket.send_message({ id: 1 })
      client_socket.send_message({ id: 2 })
      client_socket.send_message({ id: 3 })

      expect(server_socket.receive_message).to eq({ id: 1 })
      expect(server_socket.receive_message).to eq({ id: 2 })
      expect(server_socket.receive_message).to eq({ id: 3 })
    end

    it "handles messages with unicode content" do
      client_socket.send_message({ emoji: "🎉", text: "日本語" })
      message = server_socket.receive_message

      expect(message).to eq({ emoji: "🎉", text: "日本語" })
    end
  end

  describe "#close" do
    it "closes the underlying IO" do
      expect(@client_io).not_to be_closed
      client_socket.close
      expect(@client_io).to be_closed
    end

    it "is safe to call multiple times" do
      client_socket.close
      expect { client_socket.close }.not_to raise_error
    end
  end

  describe "#io" do
    it "exposes the underlying IO object" do
      expect(client_socket.io).to eq(@client_io)
    end
  end
end
