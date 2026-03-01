# frozen_string_literal: true

module RSpec
  module Conductor
    module Formatters
      class Plain < Base
        def handle_worker_message(_worker_process, message, _results)
          public_send(message[:type], message) if respond_to?(message[:type])
        end

        def example_passed(_message)
          print ".", :green
        end

        def example_failed(_message)
          print "F", :red
        end

        def example_retried(_message)
          print "R", :magenta
        end

        def example_pending(_message)
          print "*", :yellow
        end

        private

        def print(string, color)
          $stdout.print(colorize(string, color))
        end
      end
    end
  end
end
