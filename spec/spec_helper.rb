# frozen_string_literal: true

require "rspec/conductor"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.run_all_when_everything_filtered = true
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
