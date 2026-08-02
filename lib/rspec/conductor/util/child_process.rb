# frozen_string_literal: true

require "socket"

module RSpec
  module Conductor
    module Util
      class ChildProcess
        POLL_INTERVAL = 0.01

        attr_reader :pid, :message_socket, :exit_status, :ios

        def self.fork(**args, &block)
          new(**args).fork(&block)
        end

        def self.wait_all(processes)
          until processes.all?(&:done?)
            break unless tick_all(processes)
          end

          processes.each(&:finalize)
        end

        def self.tick_all(processes, poll_interval: POLL_INTERVAL)
          processes_by_io = processes.each_with_object({}) do |process, memo|
            process.ios.reject(&:closed?).each { |io| memo[io] = process }
          end
          return false if processes_by_io.empty?

          ready, = IO.select(processes_by_io.keys, nil, nil, poll_interval)
          ready&.each { |io| processes_by_io[io].handle_available(io) }

          true
        end

        def initialize(on_stdout: nil, on_stderr: nil, on_message: nil)
          @on_stdout = on_stdout
          @on_stderr = on_stderr
          @on_message = on_message
          @pid = nil
          @exit_status = nil
          @stdout_pipe = nil
          @stderr_pipe = nil
          @stdout_buffer = +""
          @stderr_buffer = +""
          @message_socket = nil
          @ios = []
          @done = false
        end

        def fork(&block)
          raise ArgumentError, '.fork should be called with a block' unless block_given?

          stdout_read, stdout_write = IO.pipe
          stderr_read, stderr_write = IO.pipe
          parent_socket, child_socket = Socket.pair(:UNIX, :STREAM, 0) if @on_message

          @stdout_pipe = stdout_read
          @stderr_pipe = stderr_read
          @message_socket = parent_socket
          @ios = [@stdout_pipe, @stderr_pipe, @message_socket].compact

          @pid = Kernel.fork do
            stdout_read.close
            stderr_read.close
            parent_socket&.close

            $stdout = stdout_write
            $stderr = stderr_write
            $stdin = File.open("/dev/null")
            STDOUT.reopen($stdout)
            STDERR.reopen($stderr)
            STDIN.reopen($stdin)

            begin
              yield self, child_socket
            rescue => e
              stderr_write.puts "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
              exit 1
            ensure
              stdout_write.close
              stderr_write.close
              child_socket&.close
            end

            exit 0
          end

          stdout_write.close
          stderr_write.close
          child_socket&.close

          self
        end

        def done?
          @done
        end

        def handle_available(io)
          return if done?
          return if io.closed?

          case io
          when @stdout_pipe, @stderr_pipe
            read_pipe(io)
          when @message_socket
            @on_message&.call
          end
        end

        def read_pipe(pipe)
          buffer, callback = case pipe
                             when @stdout_pipe
                               [@stdout_buffer, @on_stdout]
                             when @stderr_pipe
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

          @done = true

          process_buffer(@stdout_buffer, @on_stdout, drain_remaining: true)
          process_buffer(@stderr_buffer, @on_stderr, drain_remaining: true)

          begin
            _, status = Process.waitpid2(@pid)
            @exit_status = status.exitstatus
          rescue Errno::ECHILD
          end

          @message_socket&.close

          self
        end

        def wait
          self.class.wait_all([self])
        end

        def success?
          @exit_status == 0
        end

        private

        def process_buffer(buffer, callback, drain_remaining: false)
          while (newline_pos = buffer.index("\n"))
            # String#slice! seems like it was invented specifically for this scenario,
            # when you need to cut out a string fragment destructively
            line = buffer.slice!(0..newline_pos).chomp
            callback&.call(line)
          end

          if drain_remaining && !buffer.empty?
            callback&.call(buffer.chomp)
            buffer.clear
          end
        end
      end
    end
  end
end
