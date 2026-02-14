# frozen_string_literal: true

require "optparse"

module RSpec
  module Conductor
    class CLI
      DEFAULTS = {
        workers: Conductor.default_worker_count,
        offset: 0,
        first_is_1: Conductor.default_first_is_1?,
        seed: nil,
        fail_fast_after: nil,
        verbose: false,
        display_retry_backtraces: false,
        prefork_require: 'config/application.rb',
        postfork_require: :spec_helper,
      }.freeze

      def self.run(argv)
        new(argv).run
      end

      def initialize(argv)
        @argv = argv
        @conductor_options = DEFAULTS.dup
        @rspec_args = []
      end

      def run
        parse_arguments
        start_server
      end

      private

      def parse_arguments
        separator_index = @argv.index("--")

        if separator_index
          conductor_args = @argv[0...separator_index]
          @rspec_args = @argv[(separator_index + 1)..]
        else
          conductor_args = @argv
          @rspec_args = []
        end

        parse_conductor_options(conductor_args)
        @rspec_args.prepend(*conductor_args) # can use spec paths as positional arguments before -- for convenience
      end

      def parse_conductor_options(args)
        OptionParser.new do |opts|
          opts.banner = "Usage: rspec-conductor [options] -- [rspec options]"

          opts.on("-w", "--workers NUM", Integer, "Number of workers (default: #{DEFAULTS[:workers]})") do |n|
            @conductor_options[:workers] = n
          end

          opts.on("-o", "--offset NUM", Integer, "Worker number offset, if you need to run multiple conductors in parallel (default: 0)") do |n|
            @conductor_options[:offset] = n
          end

          opts.on("--prefork-require FILENAME", String, "Require this file before forking (default: config/application.rb)") do |f|
            @conductor_options[:prefork_require] = f
          end

          opts.on("--no-prefork-require", "Do not preload config/application.rb") do
            @conductor_options[:prefork_require] = nil
          end

          opts.on("--postfork-require FILENAME", String, "Require this file after forking (default: either rails_helper.rb or spec_helper.rb, whichever is present)") do |f|
            @conductor_options[:postfork_require] = f
          end

          opts.on("--no-postfork-require", "Do not load anything post-fork") do
            @conductor_options[:postfork_require] = nil
          end

          opts.on("--first-is-1", 'ENV["TEST_ENV_NUMBER"] for the worker 1 is "1" rather than ""') do
            @conductor_options[:first_is_1] = true
          end

          opts.on("-s", "--seed NUM", Integer, "Randomization seed") do |n|
            @conductor_options[:seed] = n
          end

          opts.on("--fail-fast-after NUM", Integer, "Fail the run after a certain number of failed specs") do |n|
            @conductor_options[:fail_fast_after] = n
          end

          opts.on("--formatter FORMATTER", ["plain", "ci", "fancy"], "Use a certain formatter") do |f|
            @conductor_options[:formatter] = f
          end

          opts.on("--display-retry-backtraces", "Display retried exception backtraces") do
            @conductor_options[:display_retry_backtraces] = true
          end

          opts.on("--verbose", "Enable debug output") do
            @conductor_options[:verbose] = true
          end

          opts.on("-h", "--help", "Show this help") do
            puts opts
            Kernel.exit
          end
        end.parse!(args)
      end

      def start_server
        Server.new(
          worker_count: @conductor_options[:workers],
          worker_number_offset: @conductor_options[:offset],
          prefork_require: @conductor_options[:prefork_require],
          postfork_require: @conductor_options[:postfork_require],
          first_is_1: @conductor_options[:first_is_1],
          seed: @conductor_options[:seed],
          fail_fast_after: @conductor_options[:fail_fast_after],
          rspec_args: @rspec_args,
          formatter: @conductor_options[:formatter],
          display_retry_backtraces: @conductor_options[:display_retry_backtraces],
          verbose: @conductor_options[:verbose],
        ).run
      end
    end
  end
end
