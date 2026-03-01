# frozen_string_literal: true

module RSpec
  module Conductor
    module DatabaseTasks
      class << self
        def create_databases(count)
          run_for_each_database(count, "Creating") do
            db_configs.each { |config| ::ActiveRecord::Tasks::DatabaseTasks.create(config) }
          end
        end

        def drop_databases(count)
          run_for_each_database(count, "Dropping") do
            db_configs.each { |config| ::ActiveRecord::Tasks::DatabaseTasks.drop(config) }
          end
        end

        def setup_databases(count)
          schema_format, schema_file = schema_format_and_file

          run_for_each_database(count, "Setting up") do
            puts "Dropping database(s)"
            db_configs.each { |config| ::ActiveRecord::Tasks::DatabaseTasks.drop(config) }

            puts "Creating database(s)"
            db_configs.each { |config| ::ActiveRecord::Tasks::DatabaseTasks.create(config) }

            puts "Loading schema"
            db_configs.each { |config| ::ActiveRecord::Tasks::DatabaseTasks.load_schema(config, schema_format, schema_file) }

            puts "Loading seed"
            ::ActiveRecord::Tasks::DatabaseTasks.load_seed
          end
        end

        private

        def first_is_1?
          RSpec::Conductor.default_first_is_1?
        end

        def db_configs
          reload_database_configuration!

          configs = ::ActiveRecord::Base.configurations.configs_for(env_name: ::Rails.env)
          raise ArgumentError, "could not find or parse configuration for the env #{::Rails.env}" unless configs.any?

          configs
        end

        def run_for_each_database(count, action, &block)
          raise ArgumentError, "count must be positive" if count < 1

          puts "#{action} #{count} test databases in parallel..."
          # Close connections before forking to avoid sharing file descriptors
          ::ActiveRecord::Base.connection_pool.disconnect!

          terminal = Conductor::Util::Terminal.new
          children = count.times.map do |i|
            worker_number = i + 1
            env_number = (first_is_1? || worker_number != 1) ? worker_number.to_s: ""
            line = terminal.line("#{worker_number}: starting...")
            stderr_buffer = +""

            on_stdout = ->(text) do
              line.update("#{worker_number}: #{text}")
            end
            on_stderr = ->(text) do
              stderr_buffer << "#{text}\n"
              line.update("#{worker_number}: [STDERR] #{text}")
            end

            process = Conductor::Util::ChildProcess.fork(on_stdout: on_stdout, on_stderr: on_stderr) do
              ENV["TEST_ENV_NUMBER"] = env_number
              puts "#{action} test database #{worker_number} of #{count} (TEST_ENV_NUMBER=#{env_number.inspect})"
              yield
            end

            { process: process, worker_number: worker_number, stderr: stderr_buffer }
          end
          Conductor::Util::ChildProcess.wait_all(children.map { |v| v[:process] })
          terminal.scroll_to_bottom

          failed_children = children.reject { |child| child[:process].success? }
          if failed_children.none?
            puts "\nSuccessfully completed #{action.downcase} for #{count} database(s)"
          else
            puts "\nCompleted with #{failed_children.length} error(s):"
            failed_children.each do |child|
              puts "Process #{child[:worker_number]}"
              puts "STDERR output:"
              child[:stderr].each_line { |line| puts "    #{line}" }
              puts
            end

            raise "Database operation failed for #{failed_children.length} worker(s)"
          end
        end

        def reload_database_configuration!
          parsed_yaml = ::Rails.application.config.load_database_yaml
          raise ArgumentError, "could not find database yaml or the yaml is empty" if parsed_yaml.empty?

          ::ActiveRecord::Base.configurations = ::ActiveRecord::DatabaseConfigurations.new(parsed_yaml)
        end

        def schema_format_and_file
          ruby_schema = File.join(::Rails.root, "db", "schema.rb")
          sql_schema = File.join(::Rails.root, "db", "structure.sql")

          if File.exist?(ruby_schema)
            [:ruby, ruby_schema]
          elsif File.exist?(sql_schema)
            [:sql, sql_schema]
          else
            raise ArgumentError, "Neither db/schema.rb nor db/structure.sql found"
          end
        end
      end
    end
  end
end

namespace :rspec_conductor do
  desc "Create parallel test databases (default: #{RSpec::Conductor.default_worker_count})"
  task :create, [:count] => %w(set_rails_env_to_test environment) do |_t, args|
    count = (args[:count] || RSpec::Conductor.default_worker_count).to_i
    RSpec::Conductor::DatabaseTasks.create_databases(count)
  end

  desc "Drop parallel test databases (default: #{RSpec::Conductor.default_worker_count})"
  task :drop, [:count] => %w(set_rails_env_to_test environment) do |_t, args|
    count = (args[:count] || RSpec::Conductor.default_worker_count).to_i
    RSpec::Conductor::DatabaseTasks.drop_databases(count)
  end

  desc "Setup parallel test databases (drop + create + schema load + seed) (default: #{RSpec::Conductor.default_worker_count})"
  task :setup, [:count] => %w(set_rails_env_to_test environment) do |_t, args|
    count = (args[:count] || RSpec::Conductor.default_worker_count).to_i
    RSpec::Conductor::DatabaseTasks.setup_databases(count)
  end

  # When RAILS_ENV is not set, Rails.env can default to development,
  # which would have reaching consequences for our setup script.
  # That's why we're forcing RAILS_ENV=test and spawning the rails task again.
  task :set_rails_env_to_test do
    if ENV['RAILS_ENV']
      require_relative "../rspec/conductor/util/terminal"
      require_relative "../rspec/conductor/util/child_process"

      unless defined?(::Rails.root) && defined?(::ActiveRecord::Tasks::DatabaseTasks)
        warn 'rspec-conductor rake tasks need a working rails environment to work with the databases'
        exit 1
      end
    else
      system({ "RAILS_ENV" => "test" }, "rake", *::Rake.application.top_level_tasks)
      exit
    end
  end
end
