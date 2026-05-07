---
description: "Use when working with CI/CD workflows (.github/workflows/main.yaml, ci-*.yaml, cd.yaml), the install-os-pkg manifest unit tests (test/features/install-os-pkg/unit/), or CI trigger logic. Covers macOS GHA runner behaviour, macOS native feature scenarios, CI matrix generation, dry-run test structure, and how to inspect workflow run results and logs."
applyTo: "test/features/install-os-pkg/unit/**, .github/workflows/*.yaml"
---

# CI, macOS GHA Runner, and Supplementary Tests

## CI Workflow Overview

| Workflow | File | Trigger | Purpose |
|---|---|---|---|
| CI/CD Orchestrator | `main.yaml` | push to `main`, PRs, `workflow_dispatch` | Runs `init` (detect) → calls composable `ci-*.yaml` and `cd.yaml` jobs |
| Continuous Deployment | `cd.yaml` | `workflow_call` from `main.yaml` | Publish to GHCR + GitHub Release |

## macOS GHA Runner

Feature scenario tests that use Docker run only on `ubuntu-latest` — macOS GHA runners cannot run Docker containers.

Features with macOS scenarios (environments referencing `macos-*` runners) run in the `test-macos` job on a native `macos-latest` runner.

### bash version on macOS

macOS ships bash 3.2. All `lib/` modules require bash ≥4. `.dev/scripts/test/run-unit.sh` handles this automatically by re-execing under a Homebrew bash ≥4 if found.

The `test-unit-native` job in `ci.yaml` installs bash ≥4 explicitly:

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

`macos` in `ci-test-feat.yaml` runs `bash "${TEST_SCRIPT}" "${{ matrix.job.feature }}" --mode macos`.

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
| `*.sh`, `*.bash`, `*.bats` | `shell.enabled` → `ci-lint / shell` |
| `src/**/devcontainer-feature.json` | `validate.enabled` → `ci-lint / json-schema` |
| `lib/**`, `test/lib/**` | `ci_test_lib.enabled` → `ci-test-lib / linux`, `/ macos` |
| `src/<f>/` or `test/<f>/` | `linux.enabled`, `linux.features[]` → `ci-test-feat / linux` matrix |
| macOS-capable feature in `features[]` | `macos.enabled`, `macos.matrix` → `ci-test-feat / macos` matrix |

On `workflow_dispatch`, flags are resolved from the dispatch inputs. First push to a new branch sets `is_force=true` which enables all jobs.

### Unit test matrix

`proman-cicd-detect` reads `test/lib/scenarios.yaml` to build `unit_env_matrix`. Adding an environment to `test/lib/scenarios.yaml` + `test/environments.yaml` automatically adds a new unit test matrix job.

`unit_macos_matrix` is derived from `test/environments.yaml` entries whose `image` matches `^macos`. The `test-unit-native` job runs on all of these runners.

### No CI changes needed for new scenarios

Adding a new scenario to `test/features/<feature>/scenarios.yaml` does not require any changes to `ci.yaml`. Feature discovery, macOS matrix generation, and standalone test dispatch are all fully automatic.

## Monitoring CI Runs (for Agents)

Use the `gh` CLI to inspect workflow runs, job results, and logs. MCP GitHub tools do not expose workflow-run APIs; use `gh` for everything run/job/log related.

### Workflow and run structure

`main.yaml` is the orchestrator — the only file with event triggers. Its jobs call the composable `ci-*.yaml` and `cd.yaml` workflows via `workflow_call`. The called workflows' jobs appear as individual entries inside the same parent run. A typical run contains:

- `init` — always runs; runs `proman-cicd-detect` and emits a single `config` JSON output
- `ci-build / source`, `ci-build / docs`
- `ci-lint / shell`, `ci-lint / json-schema`, `ci-lint / python`
- `ci-test-dev / python`
- `ci-test-lib / linux (ubuntu-24.04)`, `ci-test-lib / macos (macos-latest)`, ... (matrix)
- `ci-test-feat / linux (install-shell)`, `ci-test-feat / macos (install-homebrew)`, ... (matrix)
- `cd / ghcr`, `cd / gh-release`, `cd / gh-pages` — only on release triggers

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

`cd.enabled` is set to `true` by `proman-cicd-detect` when the push to `main` has at least one feature with an untagged version. The `cd` job runs only when `cd.enabled == true` AND all CI jobs succeeded.
