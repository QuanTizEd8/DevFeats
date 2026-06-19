# Install Framework Tests

Unit tests for the shared install script framework (`features/install.tmpl.bash` → synced `src/*/install.bash`). These exercise orchestration helpers such as `__resolve_auto_method__` and `__dep_install_*` in isolation with stubs — not full feature installs.

## Location

```
test/install/
├── *.bats              ← one file per concern (e.g. dep_install, resolve_auto_method)
├── scenarios.yaml      ← container matrix for CI (Linux only)
├── helpers/
│   ├── common.bash     ← loads lib test helpers + source_framework
│   └── source_framework.bash
└── setup_suite.bash
```

## Fixture

Tests source a synced feature `install.bash` with the final `__main__ "$@"` line removed. The default fixture is `install-jq` (`INSTALL_TEST_FIXTURE` overrides this).

Because bats `setup_file` does not share a shell with test bodies, each file calls `install_test__ensure_framework` from `setup()` (via `helpers/ensure_framework.bash`) to source the fixture once per process.

Run `just sync-src` before local runs so `src/install-jq/install.bash` exists.

## Running Locally

```bash
just sync-src
just test-install                              # all modules
just test-install-mod dep_install              # one module
just test-install-env ubuntu-24.04           # in one container (requires Docker)
just test-install-envs                       # all environments in scenarios.yaml

bash .dev/scripts/test/run-install.sh --filter "dep_" --jobs 1
```

## vs Library / Feature Tests

| Layer | Location | What it proves |
|-------|----------|----------------|
| Library unit tests | `test/lib/*.bats` | `lib/` modules via `reload_lib` |
| **Install framework tests** | `test/install/*.bats` | Template orchestration via sourced `install.bash` |
| Feature scenario tests | `test/features/<id>/` | End-to-end `install.sh` in containers |

Do not add install-framework logic to `test/lib/` or feature scenarios when stubbed unit coverage is sufficient.

## CI

The **Test Install Framework** job runs separately from **Test Library**. It downloads the `src/` artifact from build-features and runs `just test-install-env` for each entry in `test/install/scenarios.yaml`.
