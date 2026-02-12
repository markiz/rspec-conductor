# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "timeout"

describe RSpec::Conductor::Server do
  let(:spec_dir) { Dir.mktmpdir("conductor_specs") }

  after do
    FileUtils.remove_entry(spec_dir)
  end

  def create_spec_file(name, content)
    path = File.join(spec_dir, name)
    File.write(path, content)
    path
  end

  def run_server(worker_count: 1, first_is_1: false, **opts)
    read_io, write_io = IO.pipe

    pid = fork do
      read_io.close
      $stdout.reopen(write_io)
      $stderr.reopen(File::NULL)

      server = described_class.new(
        worker_count: worker_count,
        first_is_1: first_is_1,
        rspec_args: [spec_dir],
        seed: 12345,
        **opts
      )
      server.run
    end

    write_io.close

    Timeout.timeout(10) do
      output = read_io.read
      _, status = Process.wait2(pid)
      { exit_code: status.exitstatus, output: RSpec::Conductor::Util::ANSI.visible_chars(output) }
    end
  ensure
    read_io&.close unless read_io&.closed?
  end

  it "runs specs and exits successfully when all pass" do
    create_spec_file("passing_spec.rb", <<~RUBY)
      RSpec.describe "Passing" do
        it "works" do
          expect(1).to eq(1)
        end
      end
    RUBY

    result = run_server
    expect(result[:exit_code]).to eq(0)
    expect(result[:output]).to include("1 passed, 0 failed, 0 pending")
  end

  it "exits with failure when specs fail" do
    create_spec_file("failing_spec.rb", <<~RUBY)
      RSpec.describe "Failing" do
        it "fails" do
          expect(1).to eq(2)
        end
      end
    RUBY

    result = run_server
    expect(result[:exit_code]).to eq(1)
    expect(result[:output]).to include("0 passed, 1 failed, 0 pending")
  end

  it "runs multiple spec files across workers" do
    3.times do |i|
      create_spec_file("spec_#{i}_spec.rb", <<~RUBY)
        RSpec.describe "Spec #{i}" do
          it "passes" do
            expect(true).to be(true)
          end
        end
      RUBY
    end

    result = run_server(worker_count: 2)
    expect(result[:exit_code]).to eq(0)
    expect(result[:output]).to include("3 passed, 0 failed, 0 pending")
  end

  it "handles a mix of passing and failing specs" do
    create_spec_file("pass_spec.rb", <<~RUBY)
      RSpec.describe "Pass" do
        it("works") { expect(1).to eq(1) }
      end
    RUBY

    create_spec_file("fail_spec.rb", <<~RUBY)
      RSpec.describe "Fail" do
        it("breaks") { expect(1).to eq(2) }
      end
    RUBY

    result = run_server(worker_count: 2)
    expect(result[:exit_code]).to eq(1)
    expect(result[:output]).to include("1 passed, 1 failed, 0 pending")
  end

  it "tracks pending specs" do
    create_spec_file("pending_spec.rb", <<~RUBY)
      RSpec.describe "Pending" do
        it "is pending" do
          pending "not implemented"
          expect(1).to eq(2)
        end
      end
    RUBY

    result = run_server
    expect(result[:exit_code]).to eq(0)
    expect(result[:output]).to include("0 passed, 0 failed, 1 pending")
  end

  it "sets TEST_ENV_NUMBER for workers" do
    env_file = File.join(spec_dir, "env_numbers.txt")

    3.times do |i|
      create_spec_file("env_#{i}_spec.rb", <<~RUBY)
        RSpec.describe "Env #{i}" do
          it "records TEST_ENV_NUMBER" do
            sleep 0.05
            File.open("#{env_file}", "a") do |f|
              f.flock(File::LOCK_EX)
              f.puts ENV["TEST_ENV_NUMBER"].inspect
            end
            expect(true).to be(true)
          end
        end
      RUBY
    end

    result = run_server(worker_count: 3)
    expect(result[:exit_code]).to eq(0)

    env_numbers = File.readlines(env_file).map { |l| l.strip.tr('"', '') }.sort
    expect(env_numbers).to match_array(["", "2", "3"])
  end

  it "sets TEST_ENV_NUMBER with first_is_1 option" do
    env_file = File.join(spec_dir, "env_numbers.txt")

    3.times do |i|
      create_spec_file("env_#{i}_spec.rb", <<~RUBY)
        RSpec.describe "Env #{i}" do
          it "records TEST_ENV_NUMBER" do
            sleep 0.05
            File.open("#{env_file}", "a") do |f|
              f.flock(File::LOCK_EX)
              f.puts ENV["TEST_ENV_NUMBER"].inspect
            end
            expect(true).to be(true)
          end
        end
      RUBY
    end

    result = run_server(worker_count: 3, first_is_1: true)
    expect(result[:exit_code]).to eq(0)

    env_numbers = File.readlines(env_file).map { |l| l.strip.tr('"', '') }.sort
    expect(env_numbers).to match_array(["1", "2", "3"])
  end
end
