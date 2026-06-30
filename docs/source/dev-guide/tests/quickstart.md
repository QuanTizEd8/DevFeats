# Tests Quickstart

## Directory Layout

```
test/
├── environments.yaml            ← Central Docker image registry for all tests
├── features/
│   └── <feature-id>/
│       ├── scenarios.yaml       ← Test matrix (envs, modes, options) — edit this
│       ├── checks.yaml          ← Test assertions — edit this
│       └── tests/
│           └── *.sh             ← AUTO-GENERATED from checks.yaml — never edit
├── lib/
│   ├── *.bats                   ← BATS unit tests (one file per lib module)
│   ├── integration/             ← real-tool integration tier
│   ├── scenarios.yaml           ← BATS test environment matrix
│   ├── helpers/
│   │   ├── common.bash          ← reload_lib() helper
│   │   ├── stubs.bash           ← create_fake_bin(), begin/end_path_isolation()
│   │   └── json_assert.bash     ← JSON-specific assertions
│   ├── setup_suite.bash         ← bash ≥4 guard (auto-discovered by bats)
│   └── bats/                    ← Git submodules — NEVER EDIT
├── install/
│   ├── *.bats                   ← install framework unit tests (see {doc}`install`)
│   ├── scenarios.yaml           ← container matrix for install framework CI
│   └── helpers/                 ← source_framework + lib helper re-exports
│       ├── bats-core/
│       ├── bats-support/
│       ├── bats-assert/
│       └── bats-file/
└── proman/
    └── test_*.py                ← pytest tests for the build system (proman)
```

**Critical:** `test/features/*/tests/*.sh` are auto-generated from `checks.yaml` by `just sync-tests`. Never edit them manually.

## When to Add Which Test

| Change | What to write |
|--------|--------------|
| New or changed `lib/` function | `@test` block in `test/lib/<module>.bats` |
| New or changed install framework helper in `install.tmpl.bash` | `@test` in `test/install/<concern>.bats` — see {doc}`install` |
| New feature behavior (devcontainer) | New scenario in `scenarios.yaml` + checks in `checks.yaml` |
| Feature install should fail (non-zero exit) | `kind: install_failure` check in `checks.yaml` |
| Feature behavior requiring real macOS | Scenario with `envs: [macos-latest]` and `modes: [macos]` |
| Network-isolated code path | Standalone scenario with `standalone.network: none` |
| Non-root install path | Scenario with `setup: useradd -m -s /bin/bash <user>` and `devcontainer.remoteUser`/`standalone.user` |
| Build system / metadata change | `test/proman/test_*.py` |

## Running Tests

```bash
# Library unit tests (no Docker, fast)
just test-lib                         # all modules
just test-lib-mod <module>            # e.g. just test-lib-mod ospkg
just test-lib-env <env>               # in one container env, e.g. just test-lib-env alpine-current
just test-lib-envs                    # all container environments (requires Docker)

# Install framework tests (requires synced src/)
just test-install
just test-install-mod <module>        # e.g. just test-install-mod dep_install
just test-install-env <env>           # e.g. just test-install-env ubuntu-stable

# Feature scenario tests (requires Docker)
just test-feats <feature>             # all modes for one feature
just test-feats <feature> --filter <scenario>  # single scenario
just test-feats-macos <feature>       # macOS-only scenarios (requires macOS runner)

# Build system tests (no Docker)
just test-py

# All local tests (lib + Python); optionally also a feature
just test [<feature>]
```

## Workflow for a New Feature

```bash
# 1. Write scenarios and checks
vim test/features/<feature>/scenarios.yaml
vim test/features/<feature>/checks.yaml

# 2. Generate test scripts
just sync-tests <feature>

# 3. Verify generated scripts look right
cat test/features/<feature>/tests/*.sh

# 4. Run
just test-feats <feature>
```

After editing `checks.yaml`, always re-run `just sync-tests <feature>` before running tests.
