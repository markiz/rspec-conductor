# frozen_string_literal: true

require_relative "lib/rspec/conductor/version"

Gem::Specification.new do |spec|
  spec.name = "rspec-conductor"
  spec.version = RSpec::Conductor::VERSION
  spec.authors = ["Mark Abramov"]
  spec.email = ["me@markabramov.me"]

  spec.summary = "Queue-based parallel test runner for rspec"
  spec.description = "Queue-based parallel test runner for rspec"
  spec.homepage = "https://github.com/markiz/rspec-conductor"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/markiz/rspec-conductor/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|spec)/|\.(?:git|github))})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_dependency "rspec-core", ">= 3.8.0"
end
