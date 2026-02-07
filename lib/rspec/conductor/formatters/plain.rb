module RSpec
  module Conductor
    module Formatters
      class Plain
        include Util::ANSI

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
          if $stdout.tty?
            $stdout.print(colorize(string, color))
          else
            $stdout.print(string)
          end
        end
      end
    end
  end
end
