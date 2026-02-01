# frozen_string_literal: true

module RSpec
  module Conductor
    module Util
      class ChildProcess
        attr_reader :pid, :exit_status

        def self.fork(**args, &block)
          new(**args).fork(&block)
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

        def initialize(on_stdout: nil, on_stderr: nil)
          @on_stdout = on_stdout
          @on_stderr = on_stderr
          @pid = nil
          @exit_status = nil
          @stdout_pipe = nil
          @stderr_pipe = nil
          @stdout_buffer = String.new(encoding: Encoding.default_external)
          @stderr_buffer = String.new(encoding: Encoding.default_external)
          @done = false
        end

        def pipes
          [@stdout_pipe, @stderr_pipe].compact
        end

        def fork(&block)
          raise ArgumentError, '.fork should be called with a block' unless block_given?

          stdout_read, stdout_write = IO.pipe
          stderr_read, stderr_write = IO.pipe

          @stdout_pipe = stdout_read
          @stderr_pipe = stderr_read

          @pid = Kernel.fork do
            stdout_read.close
            stderr_read.close

            $stdout = stdout_write
            $stderr = stderr_write
            STDOUT.reopen(stdout_write)
            STDERR.reopen(stderr_write)

            begin
              yield
            rescue => e
              stderr_write.puts "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
              exit 1
            ensure
              stdout_write.close
              stderr_write.close
            end

            exit 0
          end

          stdout_write.close
          stderr_write.close

          self
        end

        def done?
          @done
        end

        def read_available(pipe)
          return if done?
          return if pipe.closed?

          buffer, callback = if pipe == @stdout_pipe
            [@stdout_buffer, @on_stdout]
          elsif pipe == @stderr_pipe
            [@stderr_buffer, @on_stderr]
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
          return if done?

          process_buffer(@stdout_buffer, @on_stdout, partial: true)
          process_buffer(@stderr_buffer, @on_stderr, partial: true)

          _, status = Process.wait2(@pid)
          @exit_status = status.exitstatus
          @done = true
          self
        end

        def wait
          self.class.wait_all([self])
        end

        def success?
          @exit_status == 0
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
              # String#slice! seems like it was invented specifically for this scenario,
              # when you need to cut out a string fragment destructively
              line = buffer.slice!(0..newline_pos).chomp
              callback.call(line)
            end
          end
        end
      end
    end
  end
end
