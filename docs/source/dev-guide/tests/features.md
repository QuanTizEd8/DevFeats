# Feature Tests

Each feature has a unified test definition in `test/features/<feature>/scenarios.yaml` and shared test scripts in `test/features/<feature>/tests/`. The same scripts run in devcontainer mode (via the devcontainer CLI), standalone mode (direct `install.bash` in a plain Docker container), and macOS mode (native bash on a macOS runner).

## Directory layout

Every feature has a mirror directory under `test/`:

```
src/
  <feature>/            ← feature source
test/
  <feature>/
    scenarios.json      ← scenario registry
    <scenario>.sh       ← assertion script for that scenario
    <scenario>/         ← optional build context (see below)
      Dockerfile
      ...
```


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

setup_required:
  envs: [ubuntu-latest]
  modes: [devcontainer, standalone]
  setup: |
    apt-get update -qq
    apt-get install -y --no-install-recommends jq
  tests: [setup_required.sh]

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
- `setup` — optional shell commands run before `install.bash`. In standalone mode, executed inside the container before install; in devcontainer mode, baked into the generated Dockerfile as a `RUN` layer. Useful for pre-installing dependencies the feature requires (e.g., `apt-get install -y jq`).
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
just test-feats <feature>                             # all modes
just test-feats <feature> --mode devcontainer         # devcontainer only
just test-feats <feature> --mode standalone           # standalone only

# Single scenario (by name prefix)
just test-feats <feature> --filter <scenario_name>

# macOS scenarios (macOS host required)
just test-feats-macos <feature>
```

Prerequisites: Docker running, Node.js, devcontainer CLI (`npm install -g @devcontainers/cli`).


## Dev Container Tests

Tests use the **devcontainer CLI** ([`@devcontainers/cli`](https://github.com/devcontainers/cli))
as the test runner.
For each scenario it:

1. Reads the scenario's entry in `scenarios.json` as a `devcontainer.json` configuration object.
2. Creates a temporary project: writes that config as `devcontainer.json`, copies the local feature source into it, and merges any per-scenario build context files (see [Scenario build context](#scenario-build-context) below).
3. Builds and starts a container from that project.
4. Runs `<scenario>.sh` inside the container.
5. Reports each named `check` as pass or fail.

The assertions inside `<scenario>.sh` are written with `check` and `reportResults`, provided by the `dev-container-features-test-lib` helper. The CLI injects this library into the container at test time — it is never installed manually.



### scenarios.json

`scenarios.json` maps scenario names to **[devcontainer.json](https://containers.dev/implementors/json_reference/) configuration objects**. The CLI writes each entry verbatim as the `devcontainer.json` for its test container, so any property valid in `devcontainer.json` is valid here.

**The only required field is `"features"`.** The base image is specified with either `"image"` (a plain image pull) or `"build"` (a Dockerfile build):

```jsonc
{
    // Plain image — simplest form, no Dockerfile needed
    "<scenario-name>": {
        "image": "<image>",
        "features": {
            "<feature-dir>": { "<option>": "<value>" }
        }
    },

    // Dockerfile build — for scenarios that require a pre-condition state
    "<other-scenario>": {
        "build": { "dockerfile": "Dockerfile" },
        "features": {
            "<feature-dir>": { "<option>": "<value>" }
        }
    }
}
```

**Feature keys** in `"features"` must be the **directory name under `src/`** — the CLI uses the key as a filesystem path to locate and copy the feature source. Per the devcontainer spec, a feature's `"id"` must match its directory name, so the key also equals the feature's `"id"`.

To reference a feature from outside this repository, use its fully-qualified registry ID (containing a `/`), e.g. `"ghcr.io/devcontainers/features/go": {}`. The CLI passes such keys through unchanged without touching local disk, which allows composing local and published features in a single scenario.

Other `devcontainer.json` properties are valid at the scenario level too. Commonly used ones:

- **`"remoteUser"`** — runs the test script as the specified user inside the container.
- **`"build": { "args": { ... } }`** — passes Docker build arguments; values can reference local environment variables with `${localEnv:VAR}`.

When a scenario uses `"build"`, it needs a corresponding `<scenario>/` subdirectory containing the referenced Dockerfile and any other build-time files — see [Scenario build context](#scenario-build-context) below.

### Scenario build context

The `<scenario>/` subdirectory is the **build context** for a `"build"`-based scenario. If the directory exists, the CLI merges its entire contents directly into the temporary `.devcontainer/` folder — the contents land flat in `.devcontainer/`, not inside a nested subfolder:

```
test/<feature>/<scenario>/          →   $TMP/.devcontainer/
  Dockerfile                        →     Dockerfile
  setup.sh                          →     setup.sh
  data/seed.sql                     →     data/seed.sql
```

Every file in the subdirectory is therefore `COPY`-addressable from the Dockerfile using its path relative to `<scenario>/`:

```dockerfile
FROM ubuntu:latest
COPY setup.sh /tmp/setup.sh          # from <scenario>/setup.sh
COPY data/seed.sql /tmp/seed.sql     # from <scenario>/data/seed.sql
RUN bash /tmp/setup.sh
```

The Dockerfile filename is not fixed — `"build": { "dockerfile": "..." }` can reference any name, as long as the file exists in the subdirectory at that relative path. By convention this repo always uses `Dockerfile`.

The subdirectory is only needed when a scenario uses `"build"`. Scenarios that specify `"image"` pull the image directly and need no subdirectory at all. Use a Dockerfile when you need to pre-install packages, create files, set up users, or otherwise establish a pre-condition state that a plain image cannot provide.

### Scenario scripts

Each `<scenario>.sh`:

- Has the same name as its key in `scenarios.json`.
- Sources `dev-container-features-test-lib` to gain access to `check` and `reportResults`.
- Runs entirely **inside the built container**, after the feature has been installed.
- Starts with `#!/bin/bash` and `set -e`, and ends with `reportResults`.

---


### Anatomy of a scenario script

```bash
#!/bin/bash
# One-line summary of what the scenario verifies.
set -e

source dev-container-features-test-lib

# --- section heading ---
check "<description>"    <command>

reportResults
```

Use section headings (comments like `# --- foo ---`) to visually group related checks. Keep the description column aligned for readability.

### The `check` function

```
check "<description>" <command...>
```

`check` runs `<command>` and records pass/fail against `<description>`. The description is printed in the test output and identifies the assertion — make it precise and self-explanatory.

The command must exit `0` to pass. Anything that evaluates as a shell command is valid: `test ...`, `command -v ...`, `grep ...`, `bash -c '...'`, etc.

### Common assertion patterns

| Intent | Pattern |
|---|---|
| File exists | `check "..." test -f /path/to/file` |
| Directory exists | `check "..." test -d /path/to/dir` |
| File is executable | `check "..." test -x /path/to/file` |
| File is non-empty | `check "..." test -s /path/to/file` |
| Command is in PATH | `check "..." command -v <name>` |
| Command exits zero | `check "..." /path/to/cmd --flag` |
| File contains string | `check "..." grep -q "pattern" /path/to/file` |
| File contains exact line | `check "..." grep -Fq "exact string" /path/to/file` |
| Python import succeeds | `check "..." /opt/conda/envs/<name>/bin/python -c 'import <pkg>'` |
| Conda env exists | `check "..." bash -c '/opt/conda/bin/conda env list \| grep -q <name>'` |

### Using bash -c for compound checks

When a check needs pipes, subshells, string comparison, or arithmetic, wrap it in `bash -c '...'`:

```bash
# Value comparison
check "uid is 1000"     bash -c '[ "$(id -u vscode)" = "1000" ]'

# Counting occurrences
check "exactly one activation line"  bash -c '[ "$(grep -Fc "conda.sh" /root/.bashrc)" -eq 1 ]'

# Command output validation
check "conda info --base correct"    bash -c '[ "$(/opt/conda/bin/conda info --base)" = "/opt/conda" ]'
```

Be careful with quoting: single quotes inside `bash -c '...'` require escaping or use of `'\''` (end-single-quote, escaped-quote, re-open-single-quote).

```bash
check "group name is vscode"  bash -c '[ "$(id -gn vscode)" = "vscode" ]'
# If the pattern contains single quotes, break them out:
check "no dup line"  bash -c '[ "$(grep -Fc '"'"'conda.sh'"'"' /root/.bashrc)" -eq 1 ]'
```

### Negative checks

Prefix the command with `!` inside `bash -c '...'` to assert something does **not** exist or **does not** succeed:

```bash
check "tree was NOT installed"   bash -c '! command -v tree'
check "old_user was evicted"     bash -c '! id old_user > /dev/null 2>&1'
check "system command absent"    bash -c '! test -x /usr/local/bin/install-os-pkg'
```

### Dockerfile pre-conditions

When a scenario must test behavior that depends on a specific pre-existing system state, set it up using `RUN` instructions in the Dockerfile. Keep Dockerfiles minimal: only set up the exact pre-condition the scenario tests, nothing more.

**Examples:**

```dockerfile
# Scenario: reinstall — a conda installation already exists
FROM ubuntu:latest
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && curl --fail --location --retry 3 \
        --output /tmp/miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${ARCH}.sh" \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm /tmp/miniforge.sh
ENV PATH="/opt/conda/bin:${PATH}"
```

```dockerfile
# Scenario: replace_existing — a conflicting user already occupies UID 1000
FROM ubuntu:latest
RUN userdel ubuntu 2>/dev/null || true && \
    groupdel ubuntu 2>/dev/null || true && \
    useradd --uid 1000 --user-group --no-create-home --shell /bin/sh old_user
```

```dockerfile
# Scenario: update_existing — conda env pre-created, YAML then updated
FROM condaforge/miniforge3
RUN mkdir -p /tmp/test-envs \
 && printf 'name: simple\ndependencies:\n  - numpy\n' > /tmp/test-envs/simple.yml \
 && /opt/conda/bin/conda env create -f /tmp/test-envs/simple.yml \
 && printf 'name: simple\ndependencies:\n  - numpy\n  - pandas\n' > /tmp/test-envs/simple.yml
```

### Build arguments

To pass build arguments into a Dockerfile (e.g. for API tokens):

```jsonc
"<scenario>": {
    "build": {
        "dockerfile": "Dockerfile",
        "args": { "GITHUB_TOKEN": "${localEnv:GITHUB_TOKEN}" }
    },
    ...
}
```

In the Dockerfile:

```dockerfile
ARG GITHUB_TOKEN
FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
```

`${localEnv:VAR}` reads from the environment of the machine running the devcontainer CLI.

### remoteUser

Set `"remoteUser"` at the scenario level to run the test script as a specific user:

```jsonc
"apt_multi_plugins": {
    "remoteUser": "vscode",
    "build": { "dockerfile": "Dockerfile" },
    ...
}
```

This is useful when a feature's behavior differs based on the effective user (e.g. user-level shell config files).


## Linux-native scenarios

Linux-native scenarios run outside the devcontainer CLI — they use plain Docker and `test/support/assert.sh`. Use them when you need to:

- Assert that a feature install **exits non-zero** (the devcontainer CLI has no `fail_check` equivalent).
- Test **non-root install paths** by running the feature as a non-root user via `RUN_AS`.
- Test **network-isolated** behavior by setting `NETWORK=none` in the `.conf` sidecar.
- Run additional assertions before or after an install without a full devcontainer build.

### Script anatomy

```bash
#!/usr/bin/env bash
# Brief description of what this scenario verifies.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/support/assert.sh
source "${REPO_ROOT}/test/support/assert.sh"

# Negative assertion: expects install.bash to exit non-zero
fail_check "invalid method exits non-zero" \
  bash "${REPO_ROOT}/src/install-git/install.bash" --method invalid

check "git not installed" bash -c '! command -v git'

reportResults
```

### The `.conf` sidecar

An optional `<scenario>.conf` file alongside the script configures the runner:

```bash
# Docker image to use (default: ubuntu:latest)
IMAGE=ubuntu:latest

# Block all outbound network
NETWORK=none

# Root commands to run before the scenario (sets up pre-condition state)
SETUP_CMD=apt-get update -qq && apt-get install -y git && useradd -m vscode

# Run the scenario script as this user (SETUP_CMD still runs as root)
RUN_AS=vscode
```

### Running Linux-native scenarios locally

```bash
# All Linux-native scenarios for a feature
bash .dev/scripts/test/run-linux.sh <feature>

# Or via the unified dispatcher
bash .dev/scripts/test/run.sh linux <feature>

# Single scenario
bash .dev/scripts/test/run-linux.sh <feature> --filter <scenario_name>
```

CI runs Linux scenarios automatically as part of `bash .dev/scripts/test/run.sh feature <feature>`. No `ci.yaml` changes are needed when adding a new `linux/` scenario.

---

## macOS scenarios

Some features (e.g. `install-homebrew`) need to run on real macOS and cannot use Docker at all. These use native bash scripts under `test/<feature>/macos/` that run directly on a `macos-latest` GHA runner without the devcontainer CLI.

```
test/<feature>/macos/
  <scenario>.sh         native bash scenario script
test/lib/
  assert.sh             check() / fail_check() / reportResults() / shellenv_block_cleanup()
```

### Script anatomy

macOS scenario scripts source `test/support/assert.sh` instead of `dev-container-features-test-lib`. The repo root is passed as `$1`. The `check` / `reportResults` API is identical to devcontainer CLI scenarios:

```bash
#!/usr/bin/env bash
set -e
REPO_ROOT="$1"
source "${REPO_ROOT}/test/support/assert.sh"

_BREW_PREFIX="$(brew --prefix 2>/dev/null)"

_cleanup() {
  # Remove any shellenv blocks written to dotfiles by the installer
  for f in ~/.bash_profile ~/.bashrc ~/.zprofile ~/.zshrc; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

bash "${REPO_ROOT}/src/install-homebrew/install.sh"

check "brew binary present"     test -f "${_BREW_PREFIX}/bin/brew"
check "brew --version succeeds" "${_BREW_PREFIX}/bin/brew" --version

reportResults
```

The library also provides `fail_check "label" <cmd>` (passes when the command exits non-zero), `checkMultiple "label" <min> "cmd1" ["cmd2"...]` (passes if at least `<min>` commands succeed), and `shellenv_block_cleanup <file>` (removes `install-homebrew` shellenv markers from dotfiles).

### Running macOS scenarios locally

```bash
# All macOS scenarios for a feature (macOS only)
bash .dev/scripts/test/run-macos.sh <feature>

# Single scenario
bash .dev/scripts/test/run-macos.sh <feature> --filter <scenario_name>
```

No `scenarios.json` entry is needed — `run-macos.sh` discovers scripts directly from `test/<feature>/macos/*.sh`. CI runs these via the `test-macos` job in `ci.yaml` on a dedicated `macos-latest` runner.

---


## Running tests

### Prerequisites

- **Docker** — must be running and accessible.
- **Node.js / npm** — required to install the devcontainer CLI.
- **devcontainer CLI** — install once:
  ```bash
  npm install -g @devcontainers/cli
  ```

### Run all scenarios for a feature

From the **repository root**:

```bash
bash .dev/scripts/test/run.sh feature <feature-folder-name>
```

This runs all `scenarios.json` scenarios **and** any fail scenarios in one pass.

Replace `<feature-folder-name>` with the directory name under `src/`, for example:

```bash
bash .dev/scripts/test/run.sh feature install-miniforge
bash .dev/scripts/test/run.sh feature install-conda-env
bash .dev/scripts/test/run.sh feature setup-user
bash .dev/scripts/test/run.sh feature install-os-pkg
```

The CLI reads `scenarios.json` for the feature, builds each scenario image, and runs the matching `.sh` script inside it.

### Run a single scenario

```bash
devcontainer features test \
  -f <feature-folder-name> \
  --skip-autogenerated \
  --filter <scenario-name> \
  --project-folder . \
  .
```

Example — run only the `reinstall` scenario for `install-miniforge`:

```bash
devcontainer features test \
  -f install-miniforge \
  --skip-autogenerated \
  --filter reinstall \
  --project-folder . \
  .
```

### Dry-run / manifest resolution tests

`install-os-pkg` has a separate unit-test suite under `test/features/install-os-pkg/unit/` that verifies the manifest parsing and package resolution logic without building a full container. It runs against a matrix of distro images.

Run it for a specific distro:

```bash
docker run --rm \
  -v "$(pwd):/repo" \
  debian:latest \
  bash /repo/test/features/install-os-pkg/unit/run.sh
```

Replace `debian:latest` with any of `ubuntu:latest`, `alpine:latest`, `fedora:latest`, `opensuse/leap:latest`, `archlinux:latest`.

Set `PLATFORM_ID` to override auto-detection (useful on macOS where `/etc/os-release` does not exist):

```bash
docker run --rm \
  -e PLATFORM_ID=debian \
  -v "$(pwd):/repo" \
  debian:latest \
  bash /repo/test/features/install-os-pkg/unit/run.sh
```

#### Adding a dry-run test case

1. Create a subdirectory under `test/features/install-os-pkg/unit/cases/<case-name>/`.
2. Add `manifest.yaml` — the YAML manifest content to parse.
3. Add `<platform-id>.expected` files — one per distro you want to cover. Each file lists the expected package names, one per line, sorted (the runner sorts both sides before comparing). An empty file asserts zero packages are resolved. Omitting a `<platform-id>.expected` file marks the case as SKIP on that distro.

### The --skip-autogenerated flag

`bash .dev/scripts/test/run.sh feature <feature>` passes `--skip-autogenerated` automatically. If you call the devcontainer CLI directly (e.g. to run a single scenario with `--filter`), always include the flag:

```bash
devcontainer features test -f <feature> --skip-autogenerated --filter <scenario> --project-folder . .
```

Without it the CLI also runs autogenerated tests that build the feature with all default option values, which fails for features that require mandatory options (e.g. `install-os-pkg`).

Always pass `--skip-autogenerated` when invoking the devcontainer CLI directly.

---

### CI

All CI/CD runs through three workflow files:

**`cicd.yaml` — Orchestrator.** The only file with event triggers (push to `main`, PRs, `workflow_dispatch`). A `detect` job analyses changed files and computes flags and feature arrays, then calls `ci.yaml` (reusable CI) and conditionally `cd.yaml` (reusable CD) when releasable features are detected.

**`ci.yaml` — Reusable CI.** Contains all lint, validation, unit, feature, and dist test jobs. Also directly callable via `workflow_dispatch` for a standalone full-suite run.

**`cd.yaml` — Reusable CD.** Contains the publish job (sync → build artifacts → GHCR publish → GitHub Release). Directly callable via `workflow_dispatch` with `feature` + `version` inputs for a single-feature hotfix publish.

When `cicd.yaml` calls `ci.yaml`, the callee's jobs appear as individual job entries inside the same GHA run — there is no separate nested run.

**Change detection.** The `detect` job maps changed paths to which CI jobs run:

| Changed path(s) | CI jobs triggered |
|---|---|
| `*.sh`, `*.bash`, `*.bats` | `lint` |
| `src/**/devcontainer-feature.json` | `validate` |
| `lib/**`, `test/lib/**` | `unit-native`, `unit-linux` |
| `src/<f>/` or `test/<f>/` | `test-features` (matrix), `test-macos` if macOS scenarios exist |
| `install-os-pkg` in changed list | `test-os-pkg` (6-distro matrix) |
| `features/install.sh`, `features/devfeats.sh`, `scripts/build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `test-dist-*` |

On `workflow_dispatch`, all flags are forced true regardless of diff. CD runs when `cicd_detect.py` determines the push to `main` has releasable features (untagged versions in `metadata.yaml`), AND CI passed. A `workflow_dispatch` with `feature` + `version` inputs triggers a manual single-feature release.

When adding a new feature, no CI changes are needed — discovery is automatic once a `devcontainer-feature.json` and `test/` directory exist. When adding macOS scenarios, no CI changes are needed — `ci.yaml` discovers them automatically.

**Trigger manually with `gh`:**

```bash
# Full suite (no publish)
gh workflow run "CI/CD"

# Full suite (auto-detects what to release)
gh workflow run "CI/CD"

# Manual single-feature release (after CI passes)
gh workflow run "CI/CD" --field feature=install-pixi --field version=1.2.3

# CI only (standalone, runs all tests)
gh workflow run "CI"
```

To watch the most recent run:

```bash
gh run watch
```

List recent runs:

```bash
gh run list --workflow "CI/CD"
```

---


## CI Workflow Overview

| Workflow | File | Trigger | Purpose |
|---|---|---|---|
| CI/CD Orchestrator | `main.yaml` | push to `main`, PRs, `workflow_dispatch` | Runs `init` (detect) → calls composable reusable workflows |
| Continuous Deployment | `deploy.yaml` | `workflow_call` from `main.yaml` | Publish to GHCR + GitHub Release + GH Pages |

## macOS GHA Runner

Feature scenario tests that use Docker run only on `ubuntu-latest` — macOS GHA runners cannot run Docker containers.

Features with macOS scenarios (environments referencing `macos-*` runners) run in the `test-macos` job on a native `macos-latest` runner.

### bash version on macOS

macOS ships bash 3.2. All `lib/` modules require bash ≥4. `.dev/scripts/test/run-unit.sh` handles this automatically by re-execing under a Homebrew bash ≥4 if found.

The `test-unit-native` job in `test-lib.yaml` installs bash ≥4 explicitly:

```yaml
- name: Install bash ≥4
  run: brew install bash
```

For local development: `brew install bash`.

### macOS-specific test behaviour

macOS has no `/etc/os-release`, so kernel/platform/distro detection uses `uname -s` fallbacks. Expected values for macOS-targeting unit tests:

| Function | macOS return value |
|---|---|
| `os__kernel` | `Darwin` |
| `os__platform` | `macos` |
| `os__id` | *(empty — no os-release)* |
| `os__font_dir` (as root) | `/Library/Fonts` |
| `os__font_dir` (non-root, no `$XDG_DATA_HOME`) | `${HOME}/Library/Fonts` |

## macOS Feature Scenarios

Features with macOS environments in their `test/features/<feature>/scenarios.yaml` are automatically included in the `test-macos` CI job. The matrix is derived from `test/environments.yaml` entries whose `image` matches `^macos`.

### CI matrix generation

`proman-cicd-detect` reads all `test/features/*/scenarios.yaml` files and builds `macos_matrix`:

```json
[{"feature": "install-homebrew", "runner": "macos-latest"}, ...]
```

The `test-features-macos` job in `test-features.yaml` runs `bash "${TEST_SCRIPT}" "${{ matrix.job.feature }}" --mode macos`.

No changes to any workflow file are needed when adding a macOS scenario — discovery is fully automatic once the environment is in `test/environments.yaml` and referenced from `scenarios.yaml`.

### Trigger unit tests manually on macOS

```bash
# Local run — re-execs with Homebrew bash automatically
bash .dev/scripts/test/run-unit.sh

# Watch CI run
gh run watch
```

## install-os-pkg Unit Tests

`test/features/install-os-pkg/unit/` is a standalone test suite that verifies manifest parsing and package resolution without a full devcontainer build. It is invoked as a standard standalone scenario via `test/features/install-os-pkg/tests/dry_run.sh`.

### Directory structure

```
test/features/install-os-pkg/unit/
  run.sh                        test runner (executed inside Docker via dry_run.sh)
  cases/
    <case-name>/
      manifest.yaml             manifest content to parse
      debian.expected           expected resolved packages for platform=debian
      alpine.expected           expected resolved packages for platform=alpine
      rhel.expected             expected resolved packages for platform=rhel
      macos.expected            expected resolved packages for platform=macos
      ...
```

- Each `.expected` file lists resolved package names, one per line, **sorted alphabetically**.
- An **empty** `.expected` file asserts that zero packages are resolved on that platform.
- **Omitting** a `<platform-id>.expected` file marks the case as SKIP on that platform.

### Running unit tests

```bash
# Via the unified runner (uses ubuntu-latest container)
just test-feats install-os-pkg --mode standalone --filter dry_run

# Or directly against any distro
docker run --rm -v "$(pwd):/repo" debian:latest \
  bash /repo/test/features/install-os-pkg/unit/run.sh /repo
```

### Adding a unit test case

1. Create `test/features/install-os-pkg/unit/cases/<case-name>/`.
2. Add `manifest.yaml` with the manifest content to test.
3. Add one `<platform-id>.expected` file per distro. Sort package names alphabetically.
4. Run the dry-run suite to verify.

## CI Trigger Logic

### Change detection

`main.yaml` runs an `init` job on every event:

| Changed path(s) | Flag set / Jobs gated |
|---|---|
| `*.sh`, `*.bash`, `*.bats` | `shell.enabled` → `lint / shell` |
| `src/**/devcontainer-feature.json` | `validate.enabled` → `lint / json-schema` |
| `lib/**`, `test/lib/**` | `test_lib.enabled` → `test-lib / linux`, `/ macos` |
| `src/<f>/` or `test/<f>/` | `linux.enabled`, `linux.features[]` → `test-features / linux` matrix |
| macOS-capable feature in `features[]` | `macos.enabled`, `macos.matrix` → `test-features / macos` matrix |

On `workflow_dispatch`, flags are resolved from the dispatch inputs in `main.yaml` (see `workflow_dispatch.inputs` there). They mirror `proman-cicd-detect` knobs: lint/validate/python/docs/unit, then **library unit tests** split with `run_lib_linux` vs `run_lib_macos`, then **feature tests** with `run_features` + `features` (Linux/devcontainer-side feature set), `run_features_devcontainer`, `run_features_linux`, and `run_macos` + `macos_features` for native macOS scenarios. Formatting is not a separate flag — it runs with shell lint and with Python when those jobs are enabled. First push to a new branch sets `is_force=true` which enables all jobs (dispatch inputs are ignored for that path).

### Unit test matrix

`proman-cicd-detect` reads `test/lib/scenarios.yaml` to build `unit_env_matrix`. Adding an environment to `test/lib/scenarios.yaml` + `test/environments.yaml` automatically adds a new unit test matrix job.

`unit_macos_matrix` is derived from `test/environments.yaml` entries whose `image` matches `^macos`. The `test-unit-native` job runs on all of these runners.

### No CI changes needed for new scenarios

Adding a new scenario to `test/features/<feature>/scenarios.yaml` does not require any changes to `test-features.yaml`. Feature discovery, macOS matrix generation, and standalone test dispatch are all fully automatic.

## Monitoring CI Runs (for Agents)

Use the `gh` CLI to inspect workflow runs, job results, and logs. MCP GitHub tools do not expose workflow-run APIs; use `gh` for everything run/job/log related.

### Workflow and run structure

`main.yaml` is the orchestrator — the only file with event triggers. Its jobs call the composable reusable workflows via `workflow_call`. The called workflows' jobs appear as individual entries inside the same parent run. A typical run contains:

- `init` — always runs; runs `proman-cicd-detect` and emits a single `config` JSON output
- `build-features / features`, `build-docs / docs`
- `lint / shell`, `lint / json-schema`, `lint / python`
- `test-dev / development`
- `test-lib / linux (ubuntu-24.04)`, `test-lib / macos (macos-latest)`, ... (matrix)
- `test-features / linux (install-shell)`, `test-features / macos (install-homebrew)`, ... (matrix)
- `deploy / ghcr`, `deploy / gh-release`, `deploy / gh-pages` — only on release triggers

### Listing and identifying runs

```bash
gh run list --limit 10
gh run list --workflow "CI/CD" --branch main --status failure --limit 5
```

### Viewing run summary and job results

```bash
gh run view <run-id>
gh run view <run-id> --json jobs
gh run view <run-id> --log-failed
gh run view <run-id> --job <job-id> --log
```

### Triggering and re-running

```bash
gh workflow run "CI/CD"
gh run rerun <run-id> --failed
```

### Release and publish

`deploy.enabled` is set to `true` by `proman-cicd-detect` when the push to `main` has at least one feature with an untagged version. The `deploy` job runs only when `deploy.enabled == true` AND all CI jobs succeeded.


## Live Testing

### `_src` symlink

`_src` → `../src` lets the devcontainer CLI resolve locally built features under `.devcontainer/` while real output lives in repo-root `src/`. See `docs/dev-guide/repo-structure.md` (section on `_src`).


The dev container also has `_src → ../src` symlink under `.devcontainer/` so the devcontainer CLI can reference locally-built features during development. See {doc}`testing` for details.


`.devcontainer/` contains configuration for the **repository's own dev
container** — the container you use when working on this repo. It does not
contain feature source code.


- `.devcontainer/`: Development environment definitions.
  - `.devcontainer/devcontainer.json`: Dev container configuration.
  - `.devcontainer/_src/`: Symlink to `src/` for local feature development inside the dev container.



The `install-shell/`, `install-miniforge/`, and `install-podman/`
subdirectories each contain a `devcontainer.json` that references the local
feature via a relative path. These exist so you can open a VS Code window
scoped to a specific feature's dev container — useful for exercising the
feature interactively during development.

### The `_src` symlink

The devcontainer CLI enforces a constraint: locally-referenced features must
reside **inside** the `.devcontainer/` directory (it validates paths using
`path.relative('.devcontainer', child)` and rejects any path containing
`..`). Since `src/` lives at the repo root (not inside `.devcontainer/`), a
symlink is used to satisfy this constraint:

```
.devcontainer/_src  →  ../src
```

The symlink's apparent path (`.devcontainer/_src/install-shell`) passes the
CLI's check. At build time Node.js follows the symlink and reads the real
files from `src/`.

Per-feature `devcontainer.json` files reference features using this path:

```jsonc
{
  "features": {
    "../_src/install-shell": {}
  }
}
```

The `_` prefix signals that `_src` is infrastructure, not a real source
directory.


## Notes and tips


- **One thing per scenario.** A scenario named after its specific configuration (`strict_channel_priority`, `network_isolated`) is easier to debug than a combined one.
- **`true` is a valid check command** when you only need to assert the feature exited cleanly.
- **Use absolute paths.** Containers may have sparse `PATH`. Prefer `/usr/local/bin/mytool` over bare `mytool` in existence checks.
- **`tests/` scripts are shared.** If the same assertions work in both devcontainer and standalone modes, use one script — don't duplicate.


**Verify syntax locally before pushing:**

```bash
bash -n src/<feature>/install.bash
bash -n test/<feature>/<scenario>.sh
```

**Use absolute paths in checks.** The container may not have a rich `PATH`. For executables like `conda` or `mamba`, prefer `/opt/conda/bin/conda` over `conda`.

**`true` is a valid check command** when you are asserting that a build step succeeded and there is nothing more to inspect:

```bash
check "feature exited cleanly" true
```

**Conda env list versus directory existence** — `conda env list` parses config and is authoritative, but also check `test -d /opt/conda/envs/<name>` since directory existence is a fast lower-level confirmation.

**Test one thing per scenario.** Avoid scenarios that mix unrelated feature flags. A scenario whose name describes its configuration precisely (e.g. `strict_channel_priority`, `update_existing`) is far easier to debug than a combined scenario.

**Prefer `grep -Fq` over `grep -q`** for exact-string matching of file content to avoid regex metacharacters in paths and strings accidentally broadening or breaking the check.

**Idempotency check.** If a feature is supposed to be idempotent (e.g. `already_configured` in `setup-user`), write a scenario whose Dockerfile pre-configures the desired state and assert that the feature exits cleanly and leaves the state intact.

**`docker system prune`** between test runs clears stale image layers and frees disk space. Test images can be large (several GB for conda-based scenarios).

**Distro-specific scenarios.** Use a different `FROM` line in the Dockerfile when a scenario needs to test on a specific distro. For example, `install-miniforge/debian/Dockerfile` uses `FROM debian:latest` to exercise Debian-specific code paths.

**No parallelism within a feature.** The CLI runs scenarios for a given feature sequentially. CI parallelises across features using a matrix job.

**Network access required.** Scenarios that download packages (conda, apt, apk, etc.) require outbound internet access. There is no offline mode.

**Build cache.** The CLI invokes Docker. Docker's layer cache applies, so repeat runs of the same scenario are faster if the base image layers have not changed. Run `docker system prune` if you need a clean slate.

**`--skip-autogenerated` is always required.** This flag tells the CLI to skip its built-in autogenerated test pass (which would build the feature with all default option values). Without it some features (e.g. `install-os-pkg`, which requires a mandatory option) would fail immediately. `bash .dev/scripts/test/run.sh feature <feature>` passes this flag automatically.

**`${localEnv:VAR}` is resolved at build time.** Build args that reference local environment variables (e.g. `GITHUB_TOKEN`) must be set in the shell before running the CLI. Missing values result in empty strings being passed to Docker.

---

## References

- [Dev Containers — Feature authoring specification](https://containers.dev/implementors/features/)
- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/cli — features test command](https://github.com/devcontainers/cli/blob/main/docs/features/test.md)
- [devcontainers/cli — npm package](https://www.npmjs.com/package/@devcontainers/cli)
- [devcontainers/feature-starter — reference template](https://github.com/devcontainers/feature-starter)
- [devcontainers/feature-starter — example scenarios.json](https://github.com/devcontainers/feature-starter/blob/main/test/hello/scenarios.json)
- [`dev-container-features-test-lib` — source](https://github.com/devcontainers/cli/blob/main/src/test/dev-container-features-test-lib)
- [Dev Containers — scenarios.json schema](https://containers.dev/implementors/features/#testing)
- [devcontainers/cli — `testCommandImpl.ts` (scenarios.json parsing)](https://github.com/devcontainers/cli/blob/main/src/spec-node/featuresCLI/testCommandImpl.ts)
- [devcontainers/action — GitHub Action for CI](https://github.com/devcontainers/action)


- `docs/source/dev/testing.md` — full narrative guide with examples
- `test-gha.instructions.md` — CI workflow triggers, matrix generation
- [devcontainer CLI test framework docs](https://raw.githubusercontent.com/devcontainers/cli/refs/heads/main/docs/features/test.md)
