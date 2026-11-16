module RSpec
  module Conductor
    module ExampleStatusPersister
      # RSpec::Core::ExampleStatusPersister is a private api, but it's been fairly stable over the versions
      # we want to support, so I don't expect issues using these stubs.
      ExampleStub = Struct.new(:id, :execution_result)
      ExampleExecutionResultStub = Struct.new(:status, :run_time)

      def self.persist(example_stats, filename)
        examples = example_stats.map do |stat|
          ExampleStub.new(
            stat[:id],
            ExampleExecutionResultStub.new(stat[:status], stat[:run_time])
          )
        end
        RSpec::Core::ExampleStatusPersister.persist(examples, filename)
      end

      def self.load(filename)
        return [] unless filename
        return [] unless File.exist?(filename)

        RSpec::Core::ExampleStatusPersister.load_from(filename).map do |status_hash|
          runtime = status_hash.fetch(:run_time)
          if runtime && (match = runtime.match(/\A(\d+(.\d+)?)/))
            runtime_seconds = match[1].to_f
          else
            runtime_seconds = nil
          end

          ExampleStub.new(
            status_hash.fetch(:example_id),
            ExampleExecutionResultStub.new(
              status_hash.fetch(:status),
              runtime_seconds
            )
          )
        end
      end

      def self.example_id_to_full_path(example_id)
        return unless example_id

        filename = RSpec::Core::Example.parse_id(example_id)[0]
        return unless filename && File.exist?(filename)

        File.expand_path(filename)
      end
    end
  end
end
