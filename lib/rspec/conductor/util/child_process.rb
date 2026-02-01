# frozen_string_literal: true

module RSpec
  module Conductor
    module Util
      class ChildProcess
        attr_reader :pid, :exit_status

        def self.fork(&block)
          new.tap { |process| process.fork(&block) }
        end

        def self.wait_all(processes)
          until processes.all?(&:done?)
            pipe_to_process = processes.each_with_object({}) do |process, memo|
              process.pipes.reject(&:closed?).each { |pipe| memo[pipe] = process }
            end
            break if pipe_to_process.empty?

            ready, = IO.select(pipe_to_process.keys, nil, nil, 0.1)
            ready&.each { |pipe| pipe_to_process[pipe].read_available(pipe) }
          end

          processes.each(&:finalize)
        end

        def initialize
          @stdout_callback = nil
          @stderr_callback = nil
          @pid = nil
          @exit_status = nil
          @error_message = nil
          @stdout_pipe = nil
          @stderr_pipe = nil
          @result_pipe = nil
          @stdout_buffer = String.new
          @stderr_buffer = String.new
          @done = false
        end

        def pipes
          [@stdout_pipe, @stderr_pipe].compact
        end

        def fork(&block)
          stdout_read, stdout_write = IO.pipe
          stderr_read, stderr_write = IO.pipe
          result_read, result_write = IO.pipe

          @stdout_pipe = stdout_read
          @stderr_pipe = stderr_read
          @result_pipe = result_read

          @pid = Kernel.fork do
            stdout_read.close
            stderr_read.close
            result_read.close

            $stdout = stdout_write
            $stderr = stderr_write
            STDOUT.reopen(stdout_write)
            STDERR.reopen(stderr_write)

            begin
              block.call if block_given?
              result_write.write("OK")
            rescue => e
              result_write.write("ERROR:#{e.message}")
              exit 1
            ensure
              result_write.close
              stdout_write.close
              stderr_write.close
            end

            exit 0
          end

          stdout_write.close
          stderr_write.close
          result_write.close
        end

        def on_stdout(&block)
          @stdout_callback = block
        end

        def on_stderr(&block)
          @stderr_callback = block
        end

        def done?
          @done
        end

        def read_available(pipe)
          return if @done
          return if pipe.closed?

          buffer, callback = if pipe == @stdout_pipe
            [@stdout_buffer, @stdout_callback]
          elsif pipe == @stderr_pipe
            [@stderr_buffer, @stderr_callback]
          else
            return
          end

          begin
            data = pipe.read_nonblock(4096, exception: false)
            if data == :wait_readable
              return
            elsif data.nil? || data.empty?
              pipe.close
            else
              buffer << data
              process_buffer(buffer, callback)
            end
          rescue IOError, EOFError
            pipe.close
          end
        end

        def finalize
          return if @done

          process_buffer(@stdout_buffer, @stdout_callback, partial: true)
          process_buffer(@stderr_buffer, @stderr_callback, partial: true)

          result = @result_pipe.read
          @result_pipe.close

          _, status = Process.wait2(@pid)
          @exit_status = status.exitstatus

          if @exit_status != 0 || result.start_with?("ERROR:")
            @error_message = result.start_with?("ERROR:") ? result.sub("ERROR:", "") : "Process exited with status #{@exit_status}"
          end

          @done = true
          self
        end

        def wait
          self.class.wait_all([self])
        end

        def success?
          @exit_status == 0 && @error_message.nil?
        end

        def error_message
          @error_message
        end

        private

        def process_buffer(buffer, callback, partial: false)
          return unless callback

          if partial
            unless buffer.empty?
              callback.call(buffer.chomp)
              buffer.clear
            end
          else
            while (newline_pos = buffer.index("\n"))
              line = buffer.slice!(0..newline_pos).chomp
              callback.call(line)
            end
          end
        end
      end
    end
  end
end
