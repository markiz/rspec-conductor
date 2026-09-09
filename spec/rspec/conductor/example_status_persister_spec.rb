# frozen_string_literal: true

require "spec_helper"
require "tempfile"

describe RSpec::Conductor::ExampleStatusPersister do
  let(:examples) do
    [
      { id: './spec/rspec/conductor/protocol_spec.rb[1:1:1]', status: 'passed', run_time: 0.01 },
      { id: './spec/rspec/conductor/protocol_spec.rb[1:1:2]', status: 'failed', run_time: 0.5 },
    ]
  end

  let(:tempfile) { Tempfile.new('rspec_status') }
  subject { described_class.persist(examples, tempfile.path) }
  after { tempfile.unlink }

  it 'generates an rspec status file' do
    subject
    lines = File.readlines(tempfile.path)
    examples.each do |example|
      line = lines.detect { |line| line.include?(example[:id]) }
      expect(line).not_to be_nil
      expect(line).to include(example[:status])
      expect(line).to include(example[:run_time].to_s)
    end
  end
end
