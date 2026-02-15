## [1.0.7] - TBD

- Move all output code into the formatter base class (lay some groundwork to address some minor issues with the fancy formatter)

## [1.0.6] - 2026-02-14

- Better RSpec arguments handling, for example, --pattern and --exclude-pattern should be supported better (reported by @cb341)
- Add support for RSpec path inclusion filters (e.g. spec/hello_spec.rb:123 or spec/hello_spec.rb[1:2:1])

## [1.0.5] - 2026-02-13

- Missed one more place where unqualified `Rails` was still shadowed by `RSpec::Rails`

## [1.0.4] - 2026-02-12

- use Etc.nprocessors to determine the default worker count (reported by @coorasse)
- use env vars (RSPEC_CONDUCTOR_DEFAULT_WORKER_COUNT, RSPEC_CONDUCTOR_FIRST_IS_1) more consistently between the rake task and the cli. Meaning, if you set these env vars, you should also see the corresponding change in the cli defaults
- Fix some rake task issues in CI (reported by @cb341)
- Fix namespace clash with RSpec::Rails in the rake task (reported by @cb341)

## [1.0.3] - 2026-02-08

- rake tasks for database preparation
- some internal retooling for terminal ui inner machinery (mostly affecting the `fancy` formatter)


## [1.0.2] - 2026-01-09

- Fix --postfork-require options
- Fix worker crashes counter

## [1.0.1] - 2025-12-21

- Fix spec_helper/rails_helper path finding [Thanks @diego-aslz]
- Add --prefork-require and --no-prefork-require CLI options for non-rails apps or rails setups where loading config/application.rb is not entirely safe
- Add --postfork-require and --no-postfork-require CLI options for flexibility

## [1.0.0] - 2025-12-21

- Initial release
