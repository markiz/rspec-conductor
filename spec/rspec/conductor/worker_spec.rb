# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "timeout"

describe RSpec::Conductor::Worker do
  before do
    @server_io, @client_io = Socket.pair(:UNIX, :STREAM, 0)
  end

  after do
    @server_io&.close unless @server_io&.closed?
    @client_io&.close unless @client_io&.closed?
    spec_file.unlink
  end

  let(:server_io) { @server_io }
  let(:client_io) { @client_io }
  let(:server_socket) { RSpec::Conductor::Protocol::Socket.new(server_io) }
  let(:client_socket) { RSpec::Conductor::Protocol::Socket.new(client_io) }
  let(:spec_file) { create_spec_file(spec_content) }
  let(:spec_content) { "" }

  def create_spec_file(content)
    file = Tempfile.new(["test_spec", ".rb"])
    file.write(content)
    file.close
    file
  end

  def run_worker_in_fork
    pid = fork do
      server_io.close
      RSpec::Conductor::Worker.new(
        worker_number: 1,
        socket: client_socket,
        rspec_args: [],
        verbose: false
      ).run
    end
    client_io.close
    pid
  end

  def collect_messages
    messages = []
    while (msg = server_socket.receive_message)
      messages << msg
    end
    messages
  end

  def wait_for_worker(pid, timeout: 5)
    Timeout.timeout(timeout) { Process.wait2(pid) }
  end

  context "with a passing spec" do
    let(:spec_content) do
      <<~RUBY
        RSpec.describe "Test" do
          it "passes" do
            expect(1).to eq(1)
          end
        end
      RUBY
    end

    it "reports results" do
      pid = run_worker_in_fork

      server_socket.send_message(type: :worker_assigned_spec, file: spec_file.path)
      server_socket.send_message(type: :shutdown)

      messages = collect_messages
      wait_for_worker(pid)

      expect(messages).to match([
        hash_including(type: "example_passed", description: "Test passes", file: spec_file.path),
        hash_including(type: "spec_complete", file: spec_file.path)
      ])
    end
  end

  context "with a failing spec" do
    let(:spec_content) do
      <<~RUBY
        RSpec.describe "Failing" do
          it "fails" do
            expect(1).to eq(2)
          end
        end
      RUBY
    end

    it "reports failure with exception details" do
      pid = run_worker_in_fork

      server_socket.send_message(type: :worker_assigned_spec, file: spec_file.path)
      server_socket.send_message(type: :shutdown)

      messages = collect_messages
      wait_for_worker(pid)

      expect(messages).to match([
        hash_including(
          type: "example_failed",
          description: "Failing fails",
          file: spec_file.path,
          exception_class: "RSpec::Expectations::ExpectationNotMetError"
        ),
        hash_including(type: "spec_complete", file: spec_file.path)
      ])
    end
  end

  it "shuts down cleanly on shutdown message" do
    pid = run_worker_in_fork

    server_socket.send_message(type: :shutdown)

    _, status = wait_for_worker(pid)
    expect(status).to be_success
  end
end
