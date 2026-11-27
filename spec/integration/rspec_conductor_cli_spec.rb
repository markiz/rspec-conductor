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

  def run_conductor(args:, timeout: 10, &block)
    Dir.chdir(spec_dir) do
      cmd = [exe_path, *args, '.']
      output, status = Timeout.timeout(timeout) do
        Open3.capture2e(*cmd)
      end
      instance_exec(&block) if block
      { output: output.encode("utf-8", invalid: :replace), exit_code: status.exitstatus }
    end
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
      name: "--pattern rspec configuration option",
      specs: {
        "aaa_spec.rb" => 'RSpec.describe("AAA") { it("passes") { expect(true).to be(true) } }',
        "abb_spec.rb" => 'RSpec.describe("ABB") { it("fails") { expect(true).to be(false) } }',
      },
      args: ["--", "--pattern", "aa*_spec.rb"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "--exclude-pattern rspec configuration option",
      specs: {
        "aaa_spec.rb" => 'RSpec.describe("AAA") { it("passes") { expect(true).to be(true) } }',
        "abb_spec.rb" => 'RSpec.describe("ABB") { it("fails") { expect(true).to be(false) } }',
      },
      args: ["--", "--exclude-pattern", "ab*_spec.rb"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "--tag rspec configuration option",
      specs: {
        "aaa_spec.rb" => 'RSpec.describe("AAA") { it("passes", :to_run) { expect(true).to be(true) } }',
        "bbb_spec.rb" => 'RSpec.describe("BBB") { it("fails") { expect(true).to be(false) } }',
      },
      args: ["--", "--tag=to_run"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "run_all_when_everything_filtered rspec configuration option",
      specs: {
        "spec_helper.rb" => "RSpec.configure { |config| config.run_all_when_everything_filtered = true }",
        "aaa_spec.rb" => 'RSpec.describe("AAA") { it("does not match the tag") { expect(true).to be(true) }  }',
      },
      args: ["--postfork-require", "spec_helper.rb", "--verbose", "--", "--tag=to_run"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "run_all_when_everything_filtered inert when there is something to run",
      specs: {
        "spec_helper.rb" => "RSpec.configure { |config| config.run_all_when_everything_filtered = true }",
        "aaa_spec.rb" => 'RSpec.describe("AAA") { it("does not match the tag") { expect(true).to be(false) }; it("matches the tag", :to_run) { expect(true).to be(true) } }',
      },
      args: ["--postfork-require", "spec_helper.rb", "--verbose", "--", "--tag=to_run"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "--tag rspec configuration option used to include certain tags",
      specs: {
        "aaa_spec.rb" => 'RSpec.describe("AAA") { it("passes") { expect(true).to be(true) } }',
        "bbb_spec.rb" => 'RSpec.describe("BBB") { it("fails", :to_skip) { expect(true).to be(false) } }',
      },
      args: ["--", "--tag=~to_skip"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "inclusion filter using the colon symbol",
      specs: {
        "aaa_spec.rb" => "RSpec.describe do\nit('passes') { expect(true).to be(true) }\nit('fails') { expect(true).to be(false) }\nend",
      },
      args: ["aaa_spec.rb:2"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
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
      name: "example description containing invalid UTF-8 bytes",
      specs: {
        "binary_description_spec.rb" => <<~RUBY
          name = "r\\xFFsum\\xFF.txt".b
          RSpec.describe("archive") { it("lists \#{name}") { expect(1).to eq(1) } }
        RUBY
      },
      args: ["-w", "1"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "binary description with profile_examples and Encoding.default_internal",
      specs: {
        "spec_helper.rb" => "Encoding.default_internal = Encoding::UTF_8\nRSpec.configure { |c| c.profile_examples = 10 }\n",
        "binary_description_spec.rb" => <<~RUBY
          name = "r\\xC3\\xA9sum\\xC3\\xA9.txt".b
          RSpec.describe("archive") { it("lists \#{name}") { expect(1).to eq(1) } }
        RUBY
      },
      args: ["-w", "1", "--postfork-require", "spec_helper.rb", "--verbose"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "binary worker stdout/stderr",
      specs: {
        "server_env.rb" => "$stdout.set_encoding(Encoding::UTF_8)\n$stderr.set_encoding(Encoding::UTF_8)",
        "binary_stdout_spec.rb" => <<~RUBY
          RSpec.describe "binary stdout" do
            it("writes raw bytes") do
              $stdout.binmode
              $stdout.write("boom \\xFF\\n")
              $stdout.flush
              $stderr.binmode
              $stderr.write("boom \\xFF\\n")
              $stderr.flush
              expect(1).to eq 1
            end
          end
        RUBY
      },
      args: ["-w", "1", "--formatter", "plain", "--prefork-require", "server_env.rb"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
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
      name: "ci formatter shows something",
      specs: {
        "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }',
        "pending_spec.rb" => 'RSpec.describe("Pending") { it("waits") { pending "later"; fail } }'
      },
      args: ["-w", "1", "--formatter", "ci"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 1 pending"
    },
    {
      name: "fancy formatter shows something (doesn't crash, at least)",
      specs: {
        "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }',
        "pending_spec.rb" => 'RSpec.describe("Pending") { it("waits") { pending "later"; fail } }'
      },
      args: ["-w", "1", "--formatter", "fancy"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 1 pending"
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
    },
    {
      name: "fancy formatter with --offset",
      specs: { "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }' },
      args: ["-w", "1", "--offset", "1", "--formatter", "fancy"],
      expect_exit: 0,
      expect_output: ["Worker 2", "1 passed, 0 failed, 0 pending"]
    },
    {
      name: "syntax error in a spec file",
      specs: {
        "broken_spec.rb" => 'RSpec.describe("Broken") { it("nope") { expect(true).to be(true) }'
      },
      args: ["-w", "1"],
      expect_exit: 1,
      expect_output: [/Failures:.*broken_spec\.rb/m, /Failures:.*(?:syntax error|SyntaxError)/m, /rspec .*broken_spec\.rb/]
    },
    {
      name: "exit! in a spec file",
      specs: {
        "exit_spec.rb" => 'RSpec.describe("Exit") { it("exits immediately") { exit!(99) } }'
      },
      args: ["-w", "1"],
      expect_exit: 1,
      expect_output: ["Worker 1 crashed", "exit status 99", /Failures:.*exit_spec\.rb/m, /rspec .*exit_spec\.rb/]
    },
    {
      name: "rspec before(:suite) hooks",
      specs: {
        "spec_helper.rb" => 'RSpec.configure { |c| c.before(:suite) { $before_suite_hook_ran = true } }',
        "pass_spec.rb" => 'RSpec.describe("RSpec before suite hooks") { it("work") { expect($before_suite_hook_ran).to be(true) } }'
      },
      args: ["-w", "1", "--verbose", "--postfork-require", "spec_helper.rb"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending"
    },
    {
      name: "before(:suite) failure fails the run",
      specs: {
        "spec_helper.rb" => 'RSpec.configure { |c| c.before(:suite) { raise "before suite boom" } }',
        "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }'
      },
      args: ["-w", "1", "--postfork-require", "spec_helper.rb"],
      expect_exit: 1,
      expect_output: ["before(:suite)", "spec_helper.rb", "0 passed, 0 failed, 0 pending", "Failures:", "Suite: FAILED"]
    },
    {
      name: "after(:suite) failure fails the run",
      specs: {
        "spec_helper.rb" => 'RSpec.configure { |c| c.after(:suite) { raise "after suite boom" } }',
        "pass_spec.rb" => 'RSpec.describe("Pass") { it("works") { expect(1).to eq(1) } }'
      },
      args: ["-w", "1", "--postfork-require", "spec_helper.rb"],
      expect_exit: 1,
      expect_output: ["after(:suite)", "spec_helper.rb", "1 passed, 0 failed, 0 pending", "Failures:", "Suite: FAILED"]
    },
    {
      name: "--print-slowest param",
      specs: {
        "a_spec.rb" => "RSpec.describe('test --print-slowest') {\n it('works') { expect(true).to be(true) }\n it('fails') { expect(false).to be(true) }\n xit('pending') { expect(false).to be(true) } }"
      },
      args: ["--print-slowest", "10"],
      expect_exit: 1,
      expect_output: ["Slowest 10 specs", "test --print-slowest works", "a_spec.rb:2", "test --print-slowest fails", "a_spec.rb:3", "1 passed, 1 failed, 1 pending"]
    },
    {
      name: "--example-status-persistence",
      specs: {
        "a_spec.rb" => "RSpec.describe('test --print-slowest') {\n it('works') { expect(true).to be(true) }\n }",
      },
      args: ["--example-status-persistence", ".example_statuses"],
      expect_exit: 0,
      expect_output: "1 passed, 0 failed, 0 pending",
      expect_proc: proc do
        expect(File.exist?(".example_statuses")).to be true
        expect(File.readlines(".example_statuses").detect { |line| line.include?('passed') }).not_to be_nil
      end
    }
  ].freeze

  SCENARIOS.each do |scenario|
    it scenario[:name], :aggregate_failures do
      scenario[:specs].each { |name, content| create_spec_file(name, content) }

      result = run_conductor(args: scenario[:args], &scenario[:expect_proc])

      expect(result[:exit_code]).to eq(scenario[:expect_exit])
      Array(scenario[:expect_output]).each do |expected_output|
        if expected_output.is_a?(Regexp)
          expect(RSpec::Conductor::Util::ANSI.visible_chars(result[:output])).to match(expected_output)
        else
          expect(RSpec::Conductor::Util::ANSI.visible_chars(result[:output])).to include(expected_output)
        end
      end
    end
  end
end
