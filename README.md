# rspec-conductor

There is a common issue when running parallel spec runners with parallel-tests: since you have to decide on the list of spec files for each runner before the run starts, you don't have good control over how well the load is distributed. What ends up happening is one runner finishes after 3 minutes, another after 7 minutes, not utilizing the CPU effectively.

rspec-conductor uses a different approach, it spawns a bunch of workers, then gives each of them one spec file to run. As soon as a worker finishes, it gives them another spec file, etc.

User experience was designed to serve as a simple, almost drop-in, replacement for the parallel_tests gem.

## Demo

2x sped-up recording of what it looks like in a real project.

![rspec-conductor demo](https://github.com/user-attachments/assets/2b598635-3192-4aa0-bb39-2af01b93bb4a)

## Installation

Add to your Gemfile:

```ruby
gem 'rspec-conductor'
```

## Usage

```bash
rspec-conductor <OPTIONS> -- <RSPEC_OPTIONS> <SPEC_PATHS>
rspec-conductor --workers 10 -- --tag '~@flaky' spec
# shorthand for setting the paths when there are no rspec options is also supported
rspec-conductor --workers 10 spec
```

`--verbose` flag is especially useful for troubleshooting.

## Mechanics

Server process preloads the `rails_helper`, prepares a list of files to work, then spawns the workers, each with `ENV['TEST_ENV_NUMBER'] = <worker_number>` (same as parallel-tests). The two communicate over a standard unix socket. Message format is basically a tuple of `(size, json_payload)`. It should also be possible to run this process over the network, but I haven't found a solid usecase for this yet.

## Setting up the databases in Rails

If you want ten workers, you're going to need ten databases. Something like this in your `database.yml` file:

```yaml
test:
  primary:
    <<: *default
    database: database_test<%= ENV['TEST_ENV_NUMBER'] %>
```

That means worker number 3 is going to use database `database_test3`, worker number 4 `database_test4` and so on. Worker number 1 is special: with `--first-is-1` flag on it uses `TEST_ENV_NUMBER="1"`, but without it, it uses `TEST_ENV_NUMBER=""` (empty string).

In order to bootstrap the test databases, there is a rake task:

```bash
# Recreate and seed test databases with TEST_ENV_NUMBER 1 to 10
rails rspec_conductor:setup[10]

# If you like the first-is-1 mode, keeping your parallel test envs separate from your regular env:
RSPEC_CONDUCTOR_FIRST_IS_1=1 rails rspec_conductor:setup[10]
```

You can also set the env variable `RSPEC_CONDUCTOR_DEFAULT_WORKER_COUNT` to change the default worker count to avoid typing the quotes for the rake task arguments in zsh.

```bash
export RSPEC_CONDUCTOR_DEFAULT_WORKER_COUNT=10
rails rspec_conductor:setup # assumes [10]

```

## Development notes

* In order to make the CLI executable load and run fast, do not add any dependencies. That includes `active_support`.

## Troubleshooting

* `+[__NSCFConstantString initialize] may have been in progress in another thread when fork() was called.` on M-based Mac machines
    * This is a common issue with ruby code, compiled libraries and forking. Set `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` environment variable to work around this
* Something gets loaded that shouldn't get loaded, or in a different order
    * There are two simple ways to hook into preloads, exposed as CLI flags, `--prefork-require` (defaults to `config/application.rb`) and `--postfork-require` (defaults to either `rails_helper.rb` or `spec_helper.rb`, whichever is present on your machine). You can set any of those to whatever you need and control the load order

## FAQ

* Why not preload the whole rails environment before spawning the workers instead of just `rails_helper`?

Short answer: it's unsafe. Any file descriptors, such as db connections, redis connections and even libcurl environment (which we use for elasticsearch), are shared between all the child processes, leading to hard to debug bugs.

* Why not use any of the existing libraries? (see Prior Art section)

`test-queue` forks after loading the whole environment rather than just the `rails_helper` (see above). `ci-queue` is deprecated for rspec. `rspecq` I couldn't get working and also I didn't like the design.

## Prior Art

* [test-queue](https://github.com/tmm1/test-queue)
* [rspecq](https://github.com/skroutz/rspecq/)
* [ci-queue](https://github.com/Shopify/ci-queue/)
