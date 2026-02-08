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
