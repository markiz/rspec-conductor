# frozen_string_literal: true

require "rspec/core"
require "etc"

module RSpec
  module Conductor
    def self.root
      @root ||= Dir.pwd
    end

    def self.root=(root)
      @root = root
    end

    def self.default_worker_count
      @default_worker_count ||= if ENV['RSPEC_CONDUCTOR_DEFAULT_WORKER_COUNT'].to_i > 0
                                  ENV['RSPEC_CONDUCTOR_DEFAULT_WORKER_COUNT'].to_i
                                else
                                  Etc.nprocessors
                                end
    end

    def self.default_first_is_1?
      ENV["RSPEC_CONDUCTOR_FIRST_IS_1"] == "1"
    end
  end
end

require_relative "conductor/util/ansi"
require_relative "conductor/util/screen_buffer"
require_relative "conductor/util/terminal"
require_relative "conductor/util/child_process"
require_relative "conductor/version"
require_relative "conductor/protocol"
require_relative "conductor/server"
require_relative "conductor/worker"
require_relative "conductor/results"
require_relative "conductor/worker_process"
require_relative "conductor/cli"
require_relative "conductor/rspec_subscriber"
require_relative "conductor/formatters/base"
require_relative "conductor/formatters/plain"
require_relative "conductor/formatters/ci"
require_relative "conductor/formatters/fancy"

require_relative "conductor/ext/rspec"

if defined?(Rails)
  require_relative "conductor/railtie"
end
