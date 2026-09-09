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
    end
  end
end
