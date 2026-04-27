# CI and GitHub Actions

The automation stack lives under `.github/workflows/`.

---

## Workflow files

| Workflow | Role |
|----------|------|
| **`cicd.yaml`** | **Orchestrator.** The only file with event triggers (push to `main`, PRs, `workflow_dispatch`). Runs a `detect` job that analyses changed files and computes flags, then calls **`ci.yaml`** (reusable CI) and conditionally **`cd.yaml`** (reusable CD) when releasable features are detected. |
| **`ci.yaml`** | **Reusable CI.** Lint, metadata validation, unit tests, feature scenario tests, macOS tests, dist tests. Directly callable via `workflow_dispatch` for a standalone full-suite run. |
| **`cd.yaml`** | **Reusable CD.** Publishes features to GHCR and creates GitHub Releases. Directly callable via `workflow_dispatch` with `feature` + `version` inputs for a single-feature hotfix. |
| **`devcontainer.yaml`** | Builds and publishes the repository devcontainer image (multi-arch: amd64/arm64). |

---

## Change detection (`detect` job)

The `detect` job in `cicd.yaml` runs `python3 .github/workflows/scripts/cicd_detect.py`, which reads `.github/ci_trigger_paths.yaml`, diffs the changed files, and writes per-job run flags to `GITHUB_OUTPUT`. On `workflow_dispatch`, all flags are forced true regardless of the diff.

| Changed path(s) | CI jobs triggered |
|----------------|------------------|
| `*.sh`, `*.bash`, `*.bats` | `lint` |
| `src/**/devcontainer-feature.json` | `validate` |
| `lib/**`, `test/unit/**` | `unit-native`, `unit-linux` |
| `src/<feature>/` or `test/<feature>/` | `test-features` (matrix), `test-macos` if macOS scenarios exist |
| `install-os-pkg` in changed list | `test-os-pkg` (multi-distro matrix) |
| `features/install.sh`, `scripts/build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `test-dist-*` |

`cicd_detect.py` also enforces the **version-bump discipline** on pull requests: any PR that touches `lib/`, `features/bootstrap.sh`, or a `features/<id>/` directory must bump the corresponding `metadata.yaml` version. A failed check names the features that need a bump. See {doc}`publishing` for full versioning rules.

CD (`cd.yaml`) runs only when:
1. The push to `main` has at least one feature with an untagged version (determined by `scripts/detect-releasable.py` inside `cicd_detect.py`), **and**
2. CI passed.

---

## CI jobs

The reusable **`ci.yaml`** contains these jobs (run conditionally based on `detect` output):

| Job | Runs on | What it does |
|-----|---------|-------------|
| `prepare` | Ubuntu | `just build-dist` → uploads `src/` and `dist/` as artifacts |
| `lint` | Devcontainer image | shfmt format-check + shellcheck on all shell files |
| `validate` | Devcontainer image | `devcontainers/action` validate-only on `./src` |
| `unit-native` | Ubuntu + macOS | bats unit suite for `lib/`; installs bash ≥ 4 on macOS first |
| `unit-linux` | debian, fedora, rockylinux, alpine containers | glibc/musl compatibility |
| `test-features` | DinD (Docker-in-Docker) | feature scenario tests matrix per feature |
| `test-macos` | `macos-latest` runner | native macOS scenario tests discovered from `test/<feature>/macos/` |
| `test-os-pkg` | Multiple distro containers | `install-os-pkg` dry-run matrix |
| `test-dist-*` | Various | dist suite tests |

---

## Manual triggers

```sh
# Full CI/CD (auto-detects what to release)
gh workflow run "CI/CD"

# Manual single-feature release (CI still runs first)
gh workflow run "CI/CD" --field feature=install-pixi --field version=1.2.3

# CI only (standalone, runs all tests)
gh workflow run "CI"

# Watch the most recent run
gh run watch

# List recent runs
gh run list --workflow "CI/CD"
```

Or use the **Actions** tab in GitHub and click **Run workflow**.

Stream logs locally after a push:

```sh
just watch-gha --commit <sha>
just watch-gha --run <workflow-run-id>
```

Logs are saved under `.local/logs/gha/`.

---

## devcontainer image

The repository devcontainer image is built by `devcontainer.yaml` and used as the CI execution environment for `lint` and `validate` jobs. It is a multi-arch (amd64/arm64) image published to GHCR.

The `detect` job in `cicd.yaml` determines whether to rebuild the image or reuse the last published tag based on changes to `.devcontainer/` and the devcontainer definition files. This avoids unnecessary rebuilds while ensuring the CI image stays up to date.
