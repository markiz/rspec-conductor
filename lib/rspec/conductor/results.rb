module RSpec
  module Conductor
    class Results
      attr_accessor :examples_passed, :examples_failed, :examples_pending, :worker_crashes, :errors, :started_at, :spec_files_total, :spec_files_processed

      def initialize
        @examples_passed = 0
        @examples_failed = 0
        @examples_pending = 0
        @worker_crashes = 0
        @errors = []
        @started_at = Time.now
        @specs_started_at = nil
        @specs_completed_at = nil
        @spec_files_total = 0
        @spec_files_processed = 0
      end

      def success?
        @examples_failed.zero? && @errors.empty? && @worker_crashes.zero? && @spec_files_total == @spec_files_processed
      end

      def example_passed
        @examples_passed += 1
      end

      def example_failed(message)
        @examples_failed += 1
        @errors << message
      end

      def example_pending
        @examples_pending += 1
      end

      def spec_file_assigned
        @specs_started_at ||= Time.now
      end

      def spec_file_complete
        @spec_files_processed += 1
      end

      def spec_file_error(message)
        @errors << message
      end

      def spec_file_processed_percentage
        return 0.0 if @spec_files_total.zero?

        @spec_files_processed.to_f / @spec_files_total
      end

      def worker_crashed
        @worker_crashes += 1
      end

      def suite_complete
        @specs_completed_at ||= Time.now
      end

      def specs_runtime
        ((@specs_completed_at || Time.now) - (@specs_started_at || @started_at)).to_f
      end

      def total_runtime
        ((@specs_completed_at || Time.now) - @started_at).to_f
      end
    end
  end
end
