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


## Directory Structure

```
test/
├── environments.yaml             ← central environment registry (Linux + macOS)
├── envs/                         ← escape-hatch Dockerfiles for complex envs
│   └── <env-name>.Dockerfile
├── lib/
│   ├── *.bats                    unit tests for lib/ modules
│   ├── scenarios.yaml            BATS unit test environments
│   ├── helpers/
│   │   ├── common.bash           reload_lib() + bats library loading
│   │   └── stubs.bash            create_fake_bin() / prepend_fake_bin_path()
│   ├── setup_suite.bash          bash ≥4 guard
│   └── bats/                     git submodules — never edit
│       ├── bats-core/
│       ├── bats-support/
│       ├── bats-assert/
│       └── bats-file/
├── features/
│   └── <feature>/
│       ├── scenarios.yaml        unified test matrix (devcontainer, standalone, macOS)
│       └── tests/                shared test scripts used by all modes
│           └── *.sh
└── support/
    └── assert.sh                 check() / fail_check() / reportResults() — API-compatible with dev-container-features-test-lib
```


## Framework overview

The test suite has four layers:

| Layer | Directory | Framework | Docker required |
|-------|-----------|-----------|----------------|
| Shared library unit tests | `test/lib/` | bats-core | No |
| Feature scenario tests | `test/<feature>/` | devcontainer CLI | Yes (Linux) |
| Linux-native scenarios | `test/<feature>/linux/` | plain Docker + assert.sh | Yes (Linux) |
| macOS feature scenarios | `test/<feature>/macos/` | native bash scripts | No (macOS runner) |

This repository has three layers of tests:

| Layer | Directory | Framework | Docker required |
|---|---|---|-|
| Shared library unit tests | `test/lib/` | bats-core | No (bare distro containers in CI) |
| Feature scenario tests | `test/features/<feature>/` | devcontainer CLI + plain Docker | Yes (Linux only) |
| macOS feature scenarios | `test/features/<feature>/` (macOS envs) | native bash | No (macOS runner) |

Supplementary test types:

- **Manifest resolution unit tests** (`test/features/install-os-pkg/unit/`) — wrapped in a standard `tests/dry_run.sh` scenario; plain Docker


## Tests

Every feature that has scenarios has a matching subdirectory under `test/`.
See [Testing](testing.md) for the full guide.

`.dev/scripts/test/run.sh` is the unified test dispatcher. Its `feature <name>` subcommand wraps both the devcontainer CLI scenario tests and Linux-native fail scenarios in a single call. Other subcommands (unit, macos, linux, dry-run) delegate to the respective runners.


## When to Add Each Type of Test

| Situation | What to add |
|---|---|
| New or changed `lib/` function | Test in `test/lib/<module>.bats` |
| New feature behaviour (Linux devcontainer) | Scenario in `test/features/<feature>/scenarios.yaml` with `modes: [devcontainer]` |
| Feature install should exit non-zero | `expect_install_failure: true` + `kind: install_failure` / `pattern` in `checks.yaml` (runner validates one install) |
| URI/helper logic in `lib/` only | `test/lib/<module>.bats` — not a feature scenario |
| Non-root or network-isolated code path | Standalone scenario with `standalone.user`/`standalone.network: none` |
| Feature behaviour that requires real macOS | Scenario in `scenarios.yaml` referencing a `macos-*` environment |
| Manifest selector or package resolution change | Case under `test/features/install-os-pkg/unit/cases/<case>/` |

## Quick Reference: Running Tests

```bash
# Lib unit tests (native bash)
just test-lib                                        # all modules
bash .dev/scripts/test/run-unit.sh --module os        # single module
bash .dev/scripts/test/run-unit.sh --filter platform  # filter by test-name regex
bash .dev/scripts/test/run-unit.sh --jobs 1           # serial (debug output)

# Unit tests in distro containers (requires Docker)
just test-lib-containers                             # all environments
just test-lib-in-env alpine-3.20                     # single environment

# Feature scenario tests (devcontainer + standalone, requires Docker)
just test-feats <feature>                             # all modes
just test-feats <feature> --mode devcontainer         # devcontainer only
just test-feats <feature> --mode standalone           # standalone only
just test-feats <feature> --filter <scenario>         # single scenario

# macOS feature scenarios (requires macOS)
just test-feats-macos <feature>
```

## Framework-specific Instructions

- **`test-unit.instructions.md`** — bats framework: `reload_lib`, stubs, subprocess isolation, macOS bash ≥4, common pitfalls
- **`test-scenarios.instructions.md`** — unified scenarios: `scenarios.yaml` format, test script anatomy, environments, standalone mode, macOS scenarios
- **`test-gha.instructions.md`** — CI and GHA: workflow triggers, macOS runner, matrix generation, monitoring runs

## Further Reading

- `docs/source/dev/testing.md` — full narrative guide with examples
- [devcontainer CLI test framework docs](https://raw.githubusercontent.com/devcontainers/cli/refs/heads/main/docs/features/test.md)
