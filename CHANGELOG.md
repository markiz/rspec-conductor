## [1.0.15] - TBD

- Fix fancy formatter crash when using the --offset option
- Better error reporting for syntax errors
- Better error reporting for unhandled worker crashes
- Better error reporting for before(:suite)/after(:suite) errors
- Deprecate undocumented `--example-status-persistence-path` cli flag syntax;  `--example-status-persistence` is still there; both were accidentally working due to how ruby OptionParser parses flags, but the `-path` flag was never intended
- Partial support for run_all_when_everything_filtered config option (thx @sobrinho)
  Due to architecture limitations, it will NOT work across the entire suite, only within the same file.
- More robust handling for binary characters in stdout/stderr/spec descriptions (reported by @6temes)
  We shouldn't crash anymore if someone outputs a bunch of invalid utf-8 codepoints, or if there are
  invalid utf-8 codepoints in example descriptions.
  However, there's a huge number of ways you can still mess with the runner, for example by naming your
  file `spec/invalid\xFF_spec.rb`. Half the stdlib will refuse to work with paths like that.
  That's why I'm drawing the line at std-streams and protocol messages.

## [1.0.14] - 2026-11-16

- Fix --print-slowest crash when there are pending specs

## [1.0.13] - 2026-11-16

- Fix stdin echo not being reenabled after the program is terminated
- When --example-status-persistence flag is set and the status file is available, run slowest spec files first (helpful when you have a mix of super slow and super fast spec files)

## [1.0.12] - 2026-09-12

- Add --example-status-persistence option to mimic rspec example status persistence runner config and to support --only-failures on repeat runs

## [1.0.11] - 2026-08-03

- Fix a bug in 2.x that would cause an exception because of the 3.x syntax usage (`_1`) in the formatter base
- Remove a potential bottleneck when spec files run under 10ms on average
- Fix performance issue with recalculating the file/location list over and over (which would coincidentally also take around 10ms for large directories)
  - In other words, if you had a lot of super fast spec files, it will run them fast as well

## [1.0.10] - 2026-03-08

- Add --print-slowest cli param to display the slowest specs in the suite

## [1.0.9] - 2026-03-01

- Handle workers stdout/stderr better. It is no longer necessary to use --verbose to see worker output. Verbose now only controls whether you see the debug output of the workers
- For the fancy formatter, allocate one line per stdout/stderr. Not ideal, but I'm not sure what layout I'm even looking for here, since allowing to freely put stuff into stdout/stderr breaks the TUI completely
- Disable echo when running (also breaks the TUI). The side effect of this is that you probably lose ability to tactically use binding.irb in your specs, but you might want to drop into the regular rspec to do that anyway
- Way better handling of SIGINT / Ctrl-C. Child processes used to just crash when terminated via signal, now they're safely terminating
- Support double Ctrl-C to force-kill the workers (same as rspec)
- When there are spec failures, include a rerun command for failed examples (e.g. `rspec spec/some_spec.rb:28 spec/other_spec.rb:42`). It should also be possible to use rspec-conductor for those, but in my personal practice, I prefer rspec because I also want to have some interactive console during the spec run, which is not going to be possible with forked children

## [1.0.8] - 2026-02-18

- When --postfork-require is provided, use current dir instead of spec/
- Make sure before(:suite) hooks are actually called

## [1.0.7] - 2026-02-16

- Move all output code into the formatter base class (lay some groundwork to address some minor issues with the fancy formatter)
- Disable rspec's --require command line parameter. Use --prefork-require and --postfork-require in the rspec-conductor cli instead (reported by @cb341)

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
