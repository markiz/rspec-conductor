# frozen_string_literal: true

require "rspec/core"

require_relative "conductor/version"
require_relative "conductor/protocol"
require_relative "conductor/server"
require_relative "conductor/worker"
require_relative "conductor/results"
require_relative "conductor/worker_process"
require_relative "conductor/cli"
require_relative "conductor/ansi"
require_relative "conductor/rspec_subscriber"
require_relative "conductor/formatters/plain"
require_relative "conductor/formatters/ci"
require_relative "conductor/formatters/fancy"

module RSpec
  module Conductor
    def self.root
      @root ||= Dir.pwd
    end

    def self.root=(root)
      @root = root
    end
  end
end

if defined?(Rails)
  require_relative "conductor/railtie"
end
