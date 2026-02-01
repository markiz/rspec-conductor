# frozen_string_literal: true

require_relative "../rspec/conductor/util/terminal"
require_relative "../rspec/conductor/util/child_process"

namespace :rspec_conductor do
  desc "Create parallel test databases (default: 4)"
  task :create, [:count] => :environment do |_t, args|
    count = (args[:count] || 4).to_i
    RSpec::Conductor::DatabaseTasks.create_databases(count)
  end

  desc "Drop parallel test databases (default: 4)"
  task :drop, [:count] => :environment do |_t, args|
    count = (args[:count] || 4).to_i
    RSpec::Conductor::DatabaseTasks.drop_databases(count)
  end

  desc "Setup parallel test databases (create + schema load + seed) (default: 4)"
  task :setup, [:count] => :environment do |_t, args|
    count = (args[:count] || 4).to_i
    RSpec::Conductor::DatabaseTasks.setup_databases(count)
  end

  task :environment do
    if ENV['RAILS_ENV']
      Rake::Task['environment'].invoke # root-level rails environment task
    else
      # we have to spawn another process because at this point Rails.env
      # could have already defaulted to development
      system({ "RAILS_ENV" => "test" }, "rake", *Rake.application.top_level_tasks)
      exit
    end
  end
end

module RSpec
  module Conductor
    module DatabaseTasks
      class << self
        def create_databases(count)
          run_for_each_database(count, "Creating") do |worker_number, env_number|
            configs = db_configs_for_env_number(env_number)
            configs.each { |config| ActiveRecord::Tasks::DatabaseTasks.create(config) }
          end
        end

        def drop_databases(count)
          run_for_each_database(count, "Dropping") do |worker_number, env_number|
            configs = db_configs_for_env_number(env_number)
            configs.each { |config| ActiveRecord::Tasks::DatabaseTasks.drop(config) }
          end
        end

        def setup_databases(count)
          run_for_each_database(count, "Setting up") do |worker_number, env_number|
            configs = db_configs_for_env_number(env_number)
            primary_config = configs.find { |c| c.name == "primary" } || configs.first

            # Run all operations sequentially within the fork
            puts "Dropping database(s)"
            configs.each { |config| ActiveRecord::Tasks::DatabaseTasks.drop(config) }

            puts "Creating database(s)"
            configs.each { |config| ActiveRecord::Tasks::DatabaseTasks.create(config) }

            puts "Loading schema"
            if File.exist?(File.join(Rails.root, "db", "schema.rb"))
              ActiveRecord::Tasks::DatabaseTasks.load_schema(
                primary_config,
                :ruby,
                File.join(Rails.root, "db", "schema.rb")
              )
            elsif File.exist?(File.join(Rails.root, "db", "structure.sql"))
              ActiveRecord::Tasks::DatabaseTasks.load_schema(
                primary_config,
                :sql,
                File.join(Rails.root, "db", "structure.sql")
              )
            else
              raise "Neither db/schema.rb nor db/structure.sql found"
            end

            puts "Loading seed"
            ActiveRecord::Tasks::DatabaseTasks.load_seed
          end
        end

        private

        def first_is_1?
          ENV["RSPEC_CONDUCTOR_FIRST_IS_1"] == "1"
        end

        def db_configs_for_env_number(env_number)
          reload_database_configuration!

          configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
          raise ArgumentError, "could not find or parse configuration for the env #{Rails.env}" unless configs.any?

          configs
        end

        def run_for_each_database(count, action)
          puts "#{action} #{count} test databases in parallel..."

          # Close connections before forking to avoid sharing file descriptors
          ActiveRecord::Base.connection_pool.disconnect!

          terminal = RSpec::Conductor::Util::Terminal.new
          processes = []

          count.times do |i|
            worker_number = i + 1
            env_number = (first_is_1? || worker_number != 1) ? worker_number.to_s: ""
            line = terminal.line("#{worker_number}: starting...")

            process = RSpec::Conductor::Util::ChildProcess.fork do
              ENV["TEST_ENV_NUMBER"] = env_number
              puts "#{action} test database #{worker_number} of #{count} (TEST_ENV_NUMBER=#{env_number.inspect})"
              yield worker_number, env_number
            end

            process.on_stdout { |text| line.update("#{worker_number}: #{text}") }
            process.on_stderr { |text| line.update("#{worker_number}: [ERROR] #{text}") }
            processes << process
          end

          RSpec::Conductor::Util::ChildProcess.wait_all(processes)

          terminal.scroll_to_bottom

          errors = processes.reject(&:success?).map do |p|
            { worker: p.worker_number, error: p.error_message }
          end

          # Restore original database configuration in parent
          ENV.delete("TEST_ENV_NUMBER")
          reload_database_configuration!

          if errors.any?
            puts "\nCompleted with #{errors.length} error(s):"
            errors.each { |e| puts "  #{e[:worker]}: #{e[:error]}" }
            raise "Database operation failed for #{errors.length} worker(s)"
          else
            puts "\nSuccessfully completed #{action.downcase} for #{count} database(s)"
          end
        end

        def reload_database_configuration!
          parsed_yaml = Rails.application.config.load_database_yaml
          return if parsed_yaml.empty?

          ActiveRecord::Base.configurations = ActiveRecord::DatabaseConfigurations.new(parsed_yaml)
        end
      end
    end
  end
end
