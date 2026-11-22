# frozen_string_literal: true

# RSpec doesn't provide us with a good way to handle before/after suite hooks,
# doing what we can here
class RSpec::Core::Configuration
  def __run_before_suite_hooks
    RSpec.current_scope = :before_suite_hook if RSpec.respond_to?(:current_scope=)
    run_suite_hooks("a `before(:suite)` hook", @before_suite_hooks) if respond_to?(:run_suite_hooks, true)
  end

  def __run_after_suite_hooks
    RSpec.current_scope = :after_suite_hook if RSpec.respond_to?(:current_scope=)
    run_suite_hooks("an `after(:suite)` hook", @after_suite_hooks) if respond_to?(:run_suite_hooks, true)
  end
end

# RSpec doesn't provide us with a good way to handle non-example exceptions,
# such as before(:suite)/after(:suite) crashes, so we're implementing it as
# another formatter hook.
RSpec::Conductor::NonExampleExceptionNotification = Struct.new(:exception, :context_description)
class RSpec::Core::Reporter
  mod = Module.new do
    def notify_non_example_exception(exception, context_description)
      super
      notify :non_example_exception, RSpec::Conductor::NonExampleExceptionNotification.new(exception, context_description)
    end
  end

  prepend mod
end
