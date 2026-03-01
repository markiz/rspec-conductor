module RSpec
  module Conductor
    class Results
      attr_accessor :passed, :failed, :pending, :worker_crashes, :errors, :started_at, :spec_files_total, :spec_files_processed

      def initialize
        @passed = 0
        @failed = 0
        @pending = 0
        @worker_crashes = 0
        @errors = []
        @started_at = Time.now
        @specs_started_at = nil
        @specs_completed_at = nil
        @spec_files_total = 0
        @spec_files_processed = 0
      end

      def success?
        @failed.zero? && @errors.empty? && @worker_crashes.zero? && @spec_files_total == @spec_files_processed
      end

      def example_passed
        @passed += 1
      end

      def example_failed(message)
        @failed += 1
        @errors << message
      end

      def example_pending
        @pending += 1
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
