# Quickstart Guide


- `test/`: Test suite for features.
  - `test/dist/`: Tests for the distributed bundled/standalone installers.
  - `test/lib/`: Tests for the shared library (`lib/`).
    - `test/lib/bats/`: Git submodule of Bats testing framework; **NEVER EDIT THESE FILES!**
    - `test/lib/helpers/`: Helper scripts for unit tests.
    - `test/lib/setup_suite.bash`: bash ≥4 guard (auto-discovered by bats)
    - `test/lib/*.bats`: Unit tests for `lib/` modules, organized by module (one file per module, e.g. `os.bats`, `shell.bats`).
  - `test/features/<feature>/`: One directory per feature, with test scenarios for that feature.
    - `test/features/<feature>/scenarios.json`: devcontainer-cli test definitions.
    - `test/features/<feature>/<scenario>.sh`: Per-scenario assertion scripts.
    - `test/features/<feature>/<scenario>/`: Per-scenario build context (if needed), e.g. Dockerfile or other files needed at build time.




## Tests

Every feature that has scenarios has a matching subdirectory under `test/`.
See [Testing](testing.md) for the full guide.

`.dev/scripts/test/run.sh` is the unified test dispatcher. Its `feature <name>` subcommand wraps both the devcontainer CLI scenario tests and Linux-native fail scenarios in a single call. Other subcommands (unit, macos, linux, dry-run) delegate to the respective runners.
