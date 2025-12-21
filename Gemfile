# frozen_string_literal: true

source "https://rubygems.org"

gemspec

if ENV["RSPEC_VERSION"].to_s.empty?
  gem "rspec", ">= 3.8.0"
else
  gem "rspec", "~> #{ENV["RSPEC_VERSION"]}"
end
