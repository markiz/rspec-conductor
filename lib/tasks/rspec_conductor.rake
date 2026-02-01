# frozen_string_literal: true

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

        def env_name
          ENV['RAILS_ENV'] ||= 'test'
        end

        def db_configs_for_env_number(env_number)
          ENV["TEST_ENV_NUMBER"] = env_number
          reload_database_configuration!

          configs = ActiveRecord::Base.configurations.configs_for(env_name: env_name)
          raise ArgumentError, "could not find or parse configuration for the env #{env_name}" unless configs.any?

          configs
        end

        def run_for_each_database(count, action)
          puts "#{action} #{count} test databases in parallel..."

          # Close connections before forking to avoid sharing file descriptors
          ActiveRecord::Base.connection_pool.disconnect!

          worker_pids = []
          result_pipes = []
          stdout_pipes = []

          count.times do |i|
            worker_number = i + 1
            env_number = if first_is_1? || worker_number != 1
              worker_number.to_s
            else
              ""
            end

            # Pipe for success/failure result
            result_read, result_write = IO.pipe
            result_pipes << result_read

            # Pipe for stdout capture
            stdout_read, stdout_write = IO.pipe
            stdout_pipes << stdout_read

            pid = fork do
              result_read.close
              stdout_read.close

              # Redirect stdout to the pipe
              $stdout = stdout_write
              $stderr = stdout_write
              STDOUT.reopen(stdout_write)
              STDERR.reopen(stdout_write)

              begin
                puts "#{action} test database #{worker_number} of #{count} (TEST_ENV_NUMBER=#{env_number.inspect})"
                yield worker_number, env_number
                result_write.write("OK")
              rescue => e
                result_write.write("ERROR:#{e.message}")
                exit 1
              ensure
                result_write.close
                stdout_write.close
              end

              exit 0
            end

            result_write.close
            stdout_write.close
            worker_pids << pid
          end

          # Parent: collect stdout from each child and prefix it
          stdout_buffers = Hash.new { |h, k| h[k] = String.new }

          # Use non-blocking IO to read from all pipes
          until stdout_pipes.all?(&:closed?)
            ready_pipes, = IO.select(stdout_pipes.reject(&:closed?), nil, nil, 0.1)

            ready_pipes&.each do |pipe|
              begin
                index = stdout_pipes.index(pipe)
                worker_number = index + 1

                data = pipe.read_nonblock(4096, exception: false)
                if data == :wait_readable
                  next
                elsif data.nil? || data.empty?
                  pipe.close
                else
                  stdout_buffers[worker_number] << data

                  # Process complete lines
                  while (newline_pos = stdout_buffers[worker_number].index("\n"))
                    line = stdout_buffers[worker_number].slice!(0..newline_pos)
                    puts "#{worker_number}: #{line}"
                  end
                end
              rescue IOError, EOFError
                pipe.close
              end
            end
          end

          # Flush any remaining partial lines
          stdout_buffers.each do |worker_number, buffer|
            puts "#{worker_number}: #{buffer}" unless buffer.empty?
          end

          # Collect results from result pipes
          errors = []
          worker_pids.each_with_index do |pid, i|
            read_pipe = result_pipes[i]
            result = read_pipe.read
            read_pipe.close

            _, status = Process.wait2(pid)

            if status.exitstatus != 0 || result.start_with?("ERROR:")
              error_msg = result.start_with?("ERROR:") ? result.sub("ERROR:", "") : "Process exited with status #{status.exitstatus}"
              errors << { worker: i + 1, error: error_msg }
            end
          end

          # Restore original database configuration in parent
          ENV.delete("TEST_ENV_NUMBER")
          reload_database_configuration!

          if errors.any?
            puts "\nCompleted with #{errors.length} error(s):"
            errors.each { |e| puts "  Worker #{e[:worker]}: #{e[:error]}" }
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
