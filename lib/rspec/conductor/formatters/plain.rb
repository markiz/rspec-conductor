module RSpec
  module Conductor
    module Formatters
      class Plain
        # TTY standard colors
        RED = 31
        GREEN = 32
        YELLOW = 33
        MAGENTA = 35
        NORMAL = 0

        def handle_worker_message(_worker, message, _results)
          public_send(message[:type], message) if respond_to?(message[:type])
        end

        def example_passed(_message)
          print ".", GREEN
        end

        def example_failed(_message)
          print "F", RED
        end

        def example_retried(_message)
          print "R", MAGENTA
        end

        def example_pending(_message)
          print "*", YELLOW
        end

        private

        def print(string, color)
          if $stdout.tty?
            $stdout.print("\e[#{color}m#{string}\e[#{NORMAL}m")
          else
            $stdout.print(string)
          end
        end
      end
    end
  end
end
