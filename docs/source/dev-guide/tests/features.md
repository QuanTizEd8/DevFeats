# Feature Tests

Each feature has a test definition under `test/features/<feature-id>/` consisting of two hand-authored YAML files and a set of auto-generated shell scripts.

## Files

| File | Edit? | Purpose |
|------|-------|---------|
| `scenarios.yaml` | ✅ Yes | Test matrix: which environments, modes, and options to run |
| `checks.yaml` | ✅ Yes | Test assertions: what commands to run to verify a scenario passed |
| `tests/*.sh` | ❌ Never | Auto-generated from `checks.yaml` by `just sync-tests` |

After editing either YAML file, regenerate the test scripts:

```bash
just sync-tests <feature-id>          # regenerate tests/*.sh
just sync-tests-check <feature-id>    # verify scripts are current (CI-style)
```

## Feature Tests vs Library Unit Tests

| Layer | Location | What it proves |
|-------|----------|----------------|
| Library unit tests | `test/lib/*.bats` | Functions in `lib/` in isolation (stubs, PATH fakes, `reload_lib`) |
| Feature scenario tests | `test/features/<id>/` | End-to-end `install.sh` / assembled `install.bash` behaviour in real containers |

**Do not put library-only logic in `test/features/`.** If a scenario never runs `install.sh` (or only sources `lib/*.sh` and calls helpers), it belongs in `test/lib/` — for example, HTTP URI resolution via a stubbed helper belongs in `test/lib/uri.bats`. Install-framework orchestration helpers belong in `test/install/` — see {doc}`/dev-guide/tests/install`.

Feature scenarios should either:
1. Let the runner call `install.sh` once with `options` from `scenarios.yaml` (default), then assert post-install state in the test script, or
2. Use `expect_install_failure: true` when the install must exit non-zero (see the `scenarios.yaml` format section below), or
3. Use `standalone.skip_install: true` only when the runner cannot perform the install you need (see below).

### When to use `skip_install`

Use `standalone.skip_install: true` only when the test script must invoke the installer under conditions the runner does not support:

- **Non-root install** — the standalone runner installs as root by default; use `standalone.user` for test assertions, then invoke `install.bash` explicitly in the test `pre` block as that user.
- **Custom CLI** — rare cases where options cannot be expressed via `scenarios.yaml` `options` (prefer exporting env vars instead).

Do **not** use `skip_install` to skip the feature install and only test `lib/` helpers — those belong in `test/lib/`.

## Shared defaults and logging

All feature scenarios inherit options from `test/features/defaults.shared.yaml` (lowest
precedence), then optional per-feature `defaults:` in `scenarios.yaml`, then scenario-level
`options:`:

| Option | Default | Role in tests |
|--------|---------|----------------|
| `log_level` | `debug` | Console verbosity during install (GHA job logs are debug-level) |
| `log_file_level` | `trace` | File verbosity (includes bash xtrace when written to `log_file`) |
| `log_file` | `/tmp/devfeats-feature.log` | In-container path for the install session log |

Dedicated `log_file` scenarios (e.g. `log_file` in `install-git`) override `log_file` with
a feature-specific path; assertions in `checks.yaml` still target that path inside the
container. The test runner always copies the install log to a canonical host file (see below).

## Install log capture

`proman-test-run` (via `just test-feats`) writes one host log per scenario key under
`.local/logs/tests/features/<scenario-key>.log` (gitignored). Layout is defined in
`.config/proman/_main.yaml` (`path.local_logs_features`).

| Mode | How the log reaches the host |
|------|------------------------------|
| **standalone** | Bind-mount `.local/logs/tests/features` at `/log-out`; install copies `${LOG_FILE}` to `/log-out/<key>.log` before the container exits |
| **devcontainer** | Install runs at image build (before mounts). Runtime bind mount via `DEVFEATS_LOG_BIND_DIR` → `/log-out`; every generated test script copies the install log from its `log_file` path onto `/log-out/<key>.log` before `reportResults` so CI can upload it |
| **macOS** | Install uses the scenario `log_file` (often under `/tmp/`); after the run, the file is copied to `.local/logs/tests/features/<key>.log` |

CI uploads each matrix log as `feat-log-<feature>-<scenario-key>-<mode>` (see
{doc}`/dev-guide/devops/ci`). When debugging CI locally, `just fetch-gha` saves GHA job
output as `<job-id>.log` and, for failed feature-test matrix jobs, the matching artifact as
`<job-id>.trace.log` beside it.

## `scenarios.yaml` Format

```yaml
# Optional per-feature defaults merged into every scenario (override shared defaults)
defaults:
  options:
    if_exists: skip

# Each top-level key is a scenario name
default_install:
  envs: [ubuntu-24.04]          # Docker image keys from test/environments.yaml
  modes: [devcontainer]         # devcontainer | standalone | macos
  tests: [default_install.sh]   # test scripts to run (from tests/)

source_build:
  envs: [ubuntu-24.04, alpine-3.21]
  modes: [devcontainer]
  options:
    method: source
    version: stable
  tests: [source_build.sh]

gitconfig_user:
  envs: [ubuntu-24.04]
  modes: [devcontainer]
  setup: useradd -m -s /bin/bash vscode   # shell commands run inside the container before install
  options:
    add_remote_user: true
    user_name: Dev User
  devcontainer:
    remoteUser: vscode   # mode-specific overrides
  tests: [gitconfig_user.sh]

network_isolated:
  envs: [ubuntu-24.04]
  modes: [standalone]
  standalone:
    network: none    # run with --network none
  tests: [network_isolated.sh]

macos_default:
  envs: [macos-latest]   # references a macOS environment in test/environments.yaml
  modes: [macos]
  tests: [macos_default.sh]

invalid_method:
  expect_install_failure: true   # assert the installer exits non-zero
  envs: [ubuntu-24.04]
  modes: [devcontainer]
  options:
    method: invalid_value
  tests: [invalid_method.sh]
```

**Scenario-level keys:**

| Key | Description |
|-----|-------------|
| `envs` | Docker image keys from `test/environments.yaml` — see that file for the full list |
| `modes` | `devcontainer`, `standalone`, `macos` — defaults to `[devcontainer, standalone]` if omitted |
| `options` | Feature option key/value pairs; merged with `defaults.options` (scenario wins) |
| `tests` | Test script names from `tests/`; all run sequentially per scenario |
| `setup` | Shell commands run inside the container before install. In standalone mode: executed before `install.sh`. In devcontainer mode: baked into the generated Dockerfile as a `RUN` layer |
| `expect_install_failure` | If `true`, asserts the installer exits non-zero; runner validates exit code and any `kind: install_failure` patterns |
| `devcontainer` | Mode-specific overrides: `remoteUser`, `containerUser` |
| `standalone` | Mode-specific overrides: `user` (run tests as this user), `sudo: false` (disable sudo for user), `network: none` (block outbound traffic), `skip_install: true` (test script calls install itself) |

**`modes`:**
- `devcontainer` — installs via the devcontainer CLI in a Docker container.
- `standalone` — runs `install.bash` directly in a plain Docker container.
- `macos` — runs on a native macOS runner.

### Devcontainer mode artifacts

For `modes` that include `devcontainer`, `proman-test-run` generates a temporary project under `.local/` (gitignored) before calling the devcontainer CLI:

| Generated artifact | Source | Edit? |
|--------------------|--------|-------|
| `scenarios.json` | `scenarios.yaml` + `test/environments.yaml` | ❌ Never — regenerated on every `just test-feats` run |
| `<scenario>/Dockerfile` | `setup` commands and environment `build.dockerfile` layers | ❌ Never |
| `tests/*.sh` | `checks.yaml` | ❌ Never — regenerate with `just sync-tests` |

Each `scenarios.json` entry is a complete `devcontainer.json` object (image/build, feature options, `remoteUser`, etc.). Hand-author **`scenarios.yaml` only** — the JSON is an implementation detail of the test runner.

## `checks.yaml` Format

```yaml
# Top-level key matches a scenario name in scenarios.yaml (or can be shared)
default_install:
  description: Default install on Ubuntu.    # optional comment in generated script
  pre: |                                      # optional: verbatim shell before checks
    export EXPECTED_VERSION="1.2.3"
  post: |                                     # optional: shell run on EXIT trap (cleanup)
    rm -f /tmp/test-artifact
  on_failure: |                               # optional: diagnostics when any check fails
    cat /var/log/installer.log
  checks:
    - title: tool on PATH                     # required: label shown in test output
      cmd: command -v tool                    # required: exits 0 to pass
    - title: version is at least 1.0
      cmd: bash -c '[ "$(tool --version | cut -d. -f1)" -ge 1 ]'
      debug: |                               # optional: unconditionally printed before this check
        echo "version output:"
        tool --version 2>&1 || true
      on_fail: |                             # optional: printed only when this check fails
        tool --version || echo "(failed)"
    - kind: fail                             # kind=fail: check passes when cmd exits non-zero
      title: tool rejects invalid input
      cmd: bash -c 'tool --invalid-flag 2>/dev/null'

invalid_method:
  description: Invalid method value causes installer to exit non-zero.
  checks:
    - kind: install_failure                  # asserts the install itself exits non-zero
      title: invalid method rejected
      pattern: "Invalid value for 'method'"  # optional: match substring in install output
```

**Check item fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `title` | ✅ | Label shown in test output |
| `cmd` | ✅ | Command to run |
| `kind` | | Assertion type: `check` (default, exits 0 passes), `fail` (exits non-zero passes), `multiple` (min N must pass), `install_failure` (asserts the install itself exits non-zero) |
| `debug` | | Shell content printed unconditionally before this check (diagnostic output) |
| `on_fail` | | Shell content run only when this specific check fails |
| `min` | | When `kind: multiple` — minimum number of commands that must exit 0 |

### `kind: install_failure` and `expect_install_failure`

`kind: install_failure` in `checks.yaml` is a check item that asserts the install exits non-zero and (optionally) that the install output matches a `pattern` substring. It is **not** emitted into the generated `.sh` file — the runner handles it directly. Any other `checks:` items in the same group that do not use `kind: install_failure` still run in the generated script (for example, verifying that a stub binary is still present after a failed install).

```yaml
# scenarios.yaml
invalid_method:
  expect_install_failure: true
  envs: [ubuntu-24.04]
  modes: [devcontainer]
  options:
    method: invalid
  tests: [invalid_method.sh]

# checks.yaml
invalid_method:
  checks:
    - kind: install_failure
      title: invalid method rejected
      pattern: "Invalid value for 'method'"
```

## Test Script Anatomy

Generated scripts (and any manually-written helper scripts for macOS or standalone) use `test/support/assert.sh`, which is API-compatible with `dev-container-features-test-lib`. The runner puts it on PATH before invoking the script:

```bash
#!/bin/bash
# One-line description of what this scenario verifies.
# AUTO-GENERATED from checks.yaml — DO NOT EDIT
set -e
. dev-container-features-test-lib

# --- basic checks ---
check "mytool is installed"       command -v mytool
check "version is correct"        bash -c "mytool --version | grep '1.2.3'"
check "config dir created"        test -d /root/.config/mytool

reportResults
```

`REPO_ROOT` is always set by the runner — use it to reference repo files from inside the container.

`reportResults` must always be the last statement; it exits non-zero if any check failed.

### Common Assertion Patterns

```bash
# Tool on PATH
check "mytool on PATH"              command -v mytool

# Version match (use grep -q or bash -c for compound checks)
check "version correct"             bash -c "mytool --version | grep -q '0.66'"

# File / directory existence
check "config dir exists"           test -d /root/.config/mytool
check "binary is executable"        test -x /usr/local/bin/mytool

# File content — use grep -Fq for literal strings, grep -q for patterns
check "PATH entry present"          grep -Fq 'export PATH' /root/.bashrc

# Value comparison (bash -c needed for arithmetic / subshell)
check "uid is 1000"                 bash -c '[ "$(id -u vscode)" = "1000" ]'

# Negative assertion — tool must NOT be present
check "tree not installed"          bash -c '! command -v tree'

# Passes when command exits non-zero (fail_check from assert.sh)
fail_check "invalid option fails"   mytool --unknown-flag
```

Use `bash -c '...'` whenever a check needs pipes, subshells, string comparison, or arithmetic. Use `grep -Fq` (fixed string) rather than `grep -q` (regex) for exact literal content checks.

`assert.sh` also provides `fail_check "label" <cmd>` (passes when the command exits non-zero) and `checkMultiple "label" <min> "cmd1" ["cmd2"...]` (passes when at least `<min>` commands exit 0).

## Test Script Generation

`just sync-tests <feature>` generates `test/features/<feature>/tests/<scenario>.sh` from `checks.yaml`. The generated scripts use `dev-container-features-test-lib` (`check` / `reportResults` functions):

```bash
#!/bin/bash
# AUTO-GENERATED from checks.yaml — DO NOT EDIT
set -e
. dev-container-features-test-lib

check "tool on PATH" command -v tool
check "tool --version succeeds" tool --version
echo "=== debug output ==="
tool --version 2>&1 || echo "(failed)"

reportResults
```

## Running Feature Tests

```bash
# All modes for a feature
just test-feats install-git

# Filter to one scenario
just test-feats install-git --filter gitconfig_system

# Standalone mode only
just test-feats install-git --mode standalone

# macOS scenarios (must be run on macOS)
just test-feats-macos install-git
```

## Test Environments

`test/environments.yaml` is the central registry of all Docker images. Each key maps to a Docker image, optionally with a build step:

```yaml
ubuntu-24.04:
  image: ubuntu:24.04

alpine-3.21+bash:
  image: alpine:3.21
  build:
    dockerfile: apk add --no-cache bash
```

Scenarios reference environment keys. The `+`-suffixed variants (e.g. `ubuntu-24.04+bash+git`) are pre-built images with extra packages for tests that need those tools available before the feature installs anything.

The `build.dockerfile` value is inline shell commands. The test runner generates `FROM <image>\nRUN <<'EOF'\nset -eux\n<commands>\nEOF` and builds the image as `devfeats-env-<name>:latest`. For macOS environments (image key starts with `macos`), the commands run as native setup on the GHA runner before tests.

Custom environments with pre-condition state (e.g. an existing user, a stub tool, or a pre-installed package) belong in `test/environments.yaml`. Never duplicate inline Dockerfiles across multiple scenario files.

```yaml
# Example: environment with a pre-created non-root user + sudo
ubuntu-24.04+vscode-user:
  image: ubuntu:24.04
  build:
    dockerfile: |
      apt-get update -qq
      apt-get install -y --no-install-recommends sudo
      useradd -m -s /bin/bash vscode
      echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Example: environment with a stub binary pre-installed
ubuntu-24.04+tool-stub:
  image: ubuntu:24.04
  build:
    dockerfile: |
      printf '#!/bin/sh\necho "mytool 0.0.0-stub"\n' > /usr/local/bin/mytool
      chmod +x /usr/local/bin/mytool
```

`test/lib/scenarios.yaml` is a separate file for the BATS unit test matrix (a subset of the environments defined in `test/environments.yaml`).

## Options Key Transformation

In standalone and macOS modes, `scenarios.yaml` option keys are converted to environment variables before `install.bash` is called. The transformation is:
- `snake_case` → `SNAKE_CASE` (e.g. `log_level` → `LOG_LEVEL`)
- `kebab-case` → `KEBAB_CASE` without hyphens (e.g. `bin-dir` → `BIN_DIR`)
- `camelCase` → `CAMELCASE` (all caps, no separator)

In devcontainer mode, keys are passed as-is to the features config object.

## CI Integration

Feature tests run in the `test-features` reusable workflow (`.github/workflows/test-features.yaml`), triggered by the main pipeline when `features/<id>/` or `lib/` changes. Each matrix job runs a single scenario (`--filter <key>`) in DinD (Linux) or on a native macOS runner.

After each job, CI uploads `.local/logs/tests/features/<scenario-key>.log` as artifact
`feat-log-<feature>-<scenario-key>-<devcontainer|linux|macos>` (`if-no-files-found: ignore`).
Use these artifacts (or `just fetch-gha` trace sidecars) when GHA step logs are too terse.

See {doc}`/dev-guide/devops/ci` for the full CI setup and log-fetch workflow.
