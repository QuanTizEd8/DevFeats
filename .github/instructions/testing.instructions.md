---
description: "Use when writing, editing, or reviewing any test file under test/. Covers the three-layer test architecture (unit tests, feature scenario tests, macOS native scenarios), directory structure, when to add each type of test, and quick-reference commands. Refer to framework-specific instruction files for full details."
applyTo: "test/**"
---

# Test Overview

This repository has three layers of tests:

| Layer | Directory | Framework | Docker required |
|---|---|---|-|
| Shared library unit tests | `test/lib/` | bats-core | No (bare distro containers in CI) |
| Feature scenario tests | `test/features/<feature>/` | devcontainer CLI + plain Docker | Yes (Linux only) |
| macOS feature scenarios | `test/features/<feature>/` (macOS envs) | native bash | No (macOS runner) |

Supplementary test types:

- **Manifest resolution unit tests** (`test/features/install-os-pkg/unit/`) — wrapped in a standard `tests/dry_run.sh` scenario; plain Docker

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

## When to Add Each Type of Test

| Situation | What to add |
|---|---|
| New or changed `lib/` function | Test in `test/lib/<module>.bats` |
| New feature behaviour (Linux devcontainer) | Scenario in `test/features/<feature>/scenarios.yaml` with `modes: [devcontainer]` |
| Feature install should exit non-zero | Standalone scenario with `standalone.skip_install: true`; use `fail_check` in the test script |
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
