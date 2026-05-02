# Quickstart Guide


- `test/`: Test suite for features.
  - `test/dist/`: Tests for the distributed bundled/standalone installers.
  - `test/unit/`: Tests for the shared library (`lib/`).
    - `test/unit/bats/`: Git submodule of Bats testing framework; **NEVER EDIT THESE FILES!**
    - `test/unit/helpers/`: Helper scripts for unit tests.
    - `test/unit/setup_suite.bash`: bash ≥4 guard (auto-discovered by bats)
    - `test/unit/*.bats`: Unit tests for `lib/` modules, organized by module (one file per module, e.g. `os.bats`, `shell.bats`).
  - `test/<feature>/`: One directory per feature, with test scenarios for that feature.
    - `test/<feature>/scenarios.json`: devcontainer-cli test definitions.
    - `test/<feature>/<scenario>.sh`: Per-scenario assertion scripts.
    - `test/<feature>/<scenario>/`: Per-scenario build context (if needed), e.g. Dockerfile or other files needed at build time.


- `.devcontainer/`: Development environment definitions.
  - `.devcontainer/devcontainer.json`: Dev container configuration.
  - `.devcontainer/_src/`: Symlink to `src/` for local feature development inside the dev container.


## Tests

Every feature that has scenarios has a matching subdirectory under `test/`.
See [Testing](testing.md) for the full guide.

`test/run.sh` is the unified test dispatcher. Its `feature <name>` subcommand wraps both the devcontainer CLI scenario tests and the fail scenarios in a single call. Other subcommands (unit, macos, dist, dry-run) delegate to the respective runners.

`test/run-fail-scenarios.sh` is the underlying runner for "expected-to-fail"
scenarios — cases where the feature should exit non-zero (e.g. invalid
inputs). It is invoked by `test/run.sh feature` and by CI.
