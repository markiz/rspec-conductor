# frozen_string_literal: true

require "spec_helper"

describe RSpec::Conductor::CLI do
  before do
    allow(RSpec::Conductor::Server).to receive(:new).and_return(instance_double(RSpec::Conductor::Server, run: nil))
  end

  it "separates conductor options from rspec options at --" do
    described_class.run(["-w", "8", "spec/models", "--", "--format", "documentation"])

    expect(RSpec::Conductor::Server).to have_received(:new) do |args|
      expect(args[:worker_count]).to eq(8)
      expect(args[:rspec_args]).to include("spec/models", "--format", "documentation")
    end
  end
end
