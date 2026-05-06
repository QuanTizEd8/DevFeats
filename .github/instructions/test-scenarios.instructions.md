---
description: "Use when writing or editing devcontainer feature test scenarios, scenarios.yaml files, test scripts in tests/, or test environments. Covers scenarios.yaml format, test script anatomy, assertion patterns, environment definitions, standalone mode, and macOS native scenarios."
applyTo: "test/features/**"
---

# Feature Scenario Tests

Each feature has a unified test definition in `test/features/<feature>/scenarios.yaml` and shared test scripts in `test/features/<feature>/tests/`. The same scripts run in devcontainer mode (via the devcontainer CLI), standalone mode (direct `install.bash` in a plain Docker container), and macOS mode (native bash on a macOS runner).

## Directory Layout

```
test/features/<feature>/
  scenarios.yaml           unified test matrix
  tests/
    <scenario>.sh          assertion script (runs in all modes)
test/environments.yaml     central environment registry
```

## `scenarios.yaml` Format

```yaml
defaults:
  options:
    log_level: trace          # merged into every scenario's options

default_install:
  envs: [ubuntu-latest]
  modes: [devcontainer, standalone]
  tests: [default_install.sh]

specific_version:
  envs: [ubuntu-latest]
  modes: [devcontainer, standalone]
  options:
    version: "1.2.3"
  tests: [specific_version.sh]

nonroot_with_sudo:
  envs: [ubuntu-latest+vscode-user]
  modes: [devcontainer, standalone]
  tests: [nonroot.sh]
  devcontainer:
    remoteUser: vscode
  standalone:
    user: vscode
    sudo: true

network_isolated:
  envs: [ubuntu-latest+offline-deps]
  modes: [standalone]
  standalone:
    network: none
  tests: [network_isolated.sh]

if_exists_fail:
  envs: [ubuntu-latest+tool-stub]
  modes: [standalone]
  options:
    if_exists: fail
  standalone:
    skip_install: true         # test script calls install.bash itself
  tests: [if_exists_fail.sh]

macos_default:
  envs: [macos-latest]         # detected via ^macos; runs natively, no modes needed
  tests: [macos_default.sh]
```

**Top-level fields:**
- `defaults` — reserved key; only `options` is supported. Values merged into every scenario.
- `envs` — array of environment names from `test/environments.yaml`. Required.
- `modes` — `[devcontainer]`, `[standalone]`, or both. Default: `[devcontainer, standalone]`. Ignored for macOS envs.
- `options` — feature option key/value pairs. Merged with `defaults.options` (scenario wins).
- `tests` — list of `.sh` filenames inside `tests/`. All run sequentially per scenario.
- `devcontainer` — devcontainer-specific config (optional):
  - `remoteUser`, `containerUser` — set in generated devcontainer scenario
- `standalone` — standalone-specific config (optional):
  - `user` — run tests (and optionally install) as this user
  - `sudo` — `false` disables sudo for `user` (default `true`)
  - `network: none` — run container with `--network none`
  - `skip_install: true` — don't call `install.bash`; test script calls it directly

## `test/environments.yaml` Format

```yaml
ubuntu-latest:
  image: ubuntu:latest

ubuntu-latest+vscode-user:
  image: ubuntu:latest
  build:
    dockerfile: |
      apt-get update -qq
      apt-get install -y --no-install-recommends sudo
      useradd -m -s /bin/bash vscode
      echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ubuntu-latest+tool-stub:
  image: ubuntu:latest
  build:
    dockerfile: |
      printf '#!/bin/sh\necho "mytool 0.0.0-stub"\n' > /usr/local/bin/mytool
      chmod +x /usr/local/bin/mytool

# macOS environment — image matches ^macos; runs natively on GHA runner
macos-latest:
  image: macos-latest
```

`build.dockerfile` is inline shell commands. The orchestrator generates `FROM <image>\nRUN <<'EOF'\nset -eux\n<commands>\nEOF` and builds `devfeats-env-<name>:latest`. For macOS environments (image matches `^macos`), `build.dockerfile` is run as native setup on the runner before tests.

Add new environments to `test/environments.yaml` — never duplicate inline Dockerfiles across multiple scenario files.

## Test Script Anatomy

```bash
#!/usr/bin/env bash
# One-line description of what this scenario verifies.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

# --- tool on PATH ---
check "mytool is installed"       command -v mytool
check "version is correct"        bash -c "mytool --version | grep '1.2.3'"
check "config dir created"        test -d /root/.config/mytool

reportResults
```

- `source dev-container-features-test-lib` — works in all modes. The standalone runner puts `test/support/assert.sh` on PATH as `dev-container-features-test-lib`.
- `REPO_ROOT` is always set by the runner — use it for paths to repo files.
- `reportResults` — required at the end; exits non-zero if any check failed.

**For negative assertions (feature must exit non-zero):**

```bash
#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

fail_check "invalid option exits non-zero" \
  bash "${REPO_ROOT}/src/<feature>/install.bash" --method invalid

reportResults
```

Use `standalone.skip_install: true` in the scenario so the runner doesn't call `install.bash` before the test script does.

## Common Assertion Patterns

```bash
# Tool on PATH
check "mytool on PATH"              command -v mytool

# Version match
check "version correct"             bash -c "mytool --version | grep '0.66'"

# File / directory existence
check "config dir exists"           test -d /root/.config/mytool
check "binary is executable"        test -x /usr/local/bin/mytool

# File content
check "contains entry"              grep -Fq "export PATH" /root/.bashrc
check "contains pattern"            grep -q "PATTERN" /path/to/file

# Value comparison
check "uid is 1000"                 bash -c '[ "$(id -u vscode)" = "1000" ]'

# Negative assertion
check "tree not installed"          bash -c '! command -v tree'

# Negative check (expects non-zero exit)
fail_check "invalid option fails"   bash "${REPO_ROOT}/src/<feat>/install.bash" --option bad
```

Use `grep -Fq` (fixed string) rather than `grep -q` (regex) for literal content checks.

## Options Key Transformation

In standalone and macOS modes, option keys are converted to env vars before calling `install.bash`:
- `log_level` → `LOG_LEVEL`
- `bin-dir` → `BIN_DIR`
- `logLevel` → `LOGLEVEL`

In devcontainer mode, keys are passed as-is to the features config object.

## macOS Native Scenarios

Reference a macOS environment (`image: macos-latest`) in `envs`. No `modes` field is needed — the runner auto-detects macOS environments. If the environment has `build.dockerfile`, those commands run as native setup on the runner.

Test scripts use the same anatomy as other modes — `source dev-container-features-test-lib` works (the runner puts `test/support/assert.sh` on PATH).

```yaml
# scenarios.yaml
macos_default:
  envs: [macos-latest]
  tests: [macos_default.sh]
```

```bash
# tests/macos_default.sh
#!/usr/bin/env bash
set -e
source dev-container-features-test-lib
bash "${REPO_ROOT}/src/<feature>/install.bash"
check "tool installed"  command -v mytool
reportResults
```

## Running Tests Locally

```bash
# All modes for a feature (devcontainer + standalone)
just test-feature <feature>
bash .dev/scripts/test/run-feature-tests.sh <feature>

# Specific mode
bash .dev/scripts/test/run-feature-tests.sh <feature> --mode devcontainer
bash .dev/scripts/test/run-feature-tests.sh <feature> --mode standalone

# Single scenario (by name prefix)
bash .dev/scripts/test/run-feature-tests.sh <feature> --filter <scenario_name>

# macOS scenarios (macOS host required)
just test-macos <feature>
bash .dev/scripts/test/run-feature-tests.sh <feature> --mode macos
```

Prerequisites: Docker running, Node.js, devcontainer CLI (`npm install -g @devcontainers/cli`).

## Notes

- **One thing per scenario.** A scenario named after its specific configuration (`strict_channel_priority`, `network_isolated`) is easier to debug than a combined one.
- **`true` is a valid check command** when you only need to assert the feature exited cleanly.
- **Use absolute paths.** Containers may have sparse `PATH`. Prefer `/usr/local/bin/mytool` over bare `mytool` in existence checks.
- **`tests/` scripts are shared.** If the same assertions work in both devcontainer and standalone modes, use one script — don't duplicate.

## Further Reading

- `docs/source/dev/testing.md` — full narrative guide with examples
- `test-gha.instructions.md` — CI workflow triggers, matrix generation
- [devcontainer CLI test framework docs](https://raw.githubusercontent.com/devcontainers/cli/refs/heads/main/docs/features/test.md)
