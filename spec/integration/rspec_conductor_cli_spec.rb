# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "timeout"

describe "rspec-conductor executable" do
  let(:spec_dir) { Dir.mktmpdir("conductor_integration") }
  let(:exe_path) { File.expand_path("../../exe/rspec-conductor", __dir__) }

  after do
    FileUtils.remove_entry(spec_dir)
  end

  def create_spec_file(name, content)
    path = File.join(spec_dir, name)
    File.write(path, content)
    path
  end

  def run_conductor(*args, timeout: 10)
    cmd = [exe_path, *args, spec_dir]
    output, status = Timeout.timeout(timeout) do
      Open3.capture2e(*cmd)
    end
    { output: output, exit_code: status.exitstatus }
  end

  SCENARIOS = [
    {
      name: "single passing spec",
      specs: { "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }' },
      args: ["-w", "1"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "single failing spec",
      specs: { "fail_spec.rb" => 'RSpec.describe("Fail") { it("breaks") { expect(1).to eq(2) } }' },
      args: ["-w", "1"],
      expect_exit: 1,
      expect_output: "0 passed, 1 failed, 0 pending"
    },
    {
      name: "multiple specs with multiple workers",
      specs: {
        "a_spec.rb" => 'RSpec.describe("A") { it("passes") { expect(true).to be(true) } }',
        "b_spec.rb" => 'RSpec.describe("B") { it("passes") { expect(true).to be(true) } }',
        "c_spec.rb" => 'RSpec.describe("C") { it("passes") { expect(true).to be(true) } }'
      },
      args: ["-w", "2"],
      expect_exit: 0,
      expect_output: "3 passed, 0 failed, 0 pending"
    },
    {
      name: "mixed results",
      specs: {
        "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }',
        "fail_spec.rb" => 'RSpec.describe("Fail") { it("breaks") { expect(1).to eq(2) } }',
        "pending_spec.rb" => 'RSpec.describe("Pending") { it("is pending") { pending "later"; fail } }'
      },
      args: ["-w", "2"],
      expect_exit: 1,
      expect_output: "1 passed, 1 failed, 1 pending"
    },
    {
      name: "with seed option",
      specs: { "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }' },
      args: ["-w", "1", "-s", "42"],
      expect_exit: 0,
      expect_output: "seed 42"
    },
    {
      name: "plain formatter shows dots",
      specs: {
        "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }',
        "fail_spec.rb" => 'RSpec.describe("Fail") { it("breaks") { expect(1).to eq(2) } }',
        "pending_spec.rb" => 'RSpec.describe("Pending") { it("waits") { pending "later"; fail } }'
      },
      args: ["-w", "1", "--formatter", "plain"],
      expect_exit: 1,
      expect_output: "1 passed, 1 failed, 1 pending"
    },
    {
      name: "ci formatter shows periodic status",
      specs: { "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }' },
      args: ["-w", "1", "--formatter", "ci"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "fancy formatter shows progress bar",
      specs: { "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }' },
      args: ["-w", "1", "--formatter", "fancy"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    }
  ].freeze

  SCENARIOS.each do |scenario|
    it scenario[:name] do
      scenario[:specs].each { |name, content| create_spec_file(name, content) }

      result = run_conductor(*scenario[:args])

      expect(result[:exit_code]).to eq(scenario[:expect_exit])
      expect(RSpec::Conductor::ANSI.visible_chars(result[:output])).to include(scenario[:expect_output])
    end
  end
end
