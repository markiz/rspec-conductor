# frozen_string_literal: true

module RSpec
  module Conductor
    class Railtie < ::Rails::Railtie
      rake_tasks do
        load File.expand_path("../../../tasks/rspec_conductor.rake", __FILE__)
      end
    end
  end
end
