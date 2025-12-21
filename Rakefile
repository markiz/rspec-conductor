# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :conductor do
  sh "exe/rspec-conductor", "-w", "4", "spec/"
end

task default: [:spec, :conductor]
