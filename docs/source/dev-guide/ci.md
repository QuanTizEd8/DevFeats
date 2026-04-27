## CI workflows — `.github/workflows/`

| File | Purpose |
|------|---------|
| `cicd.yaml` | Orchestrator: `detect`, calls `ci.yaml`, conditionally `cd.yaml` |
| `ci.yaml` | Lint, validate, unit, feature scenarios, macOS, dist tests |
| `cd.yaml` | Publish to GHCR + GitHub Release |
| `devcontainer-image.yaml` | Devcontainer image build/publish |

Jobs are selected from changed paths unless it is a full run (tag / manual). See [CI](ci.md).

CI jobs run `python3 scripts/sync-src.py` where needed so `src/` is populated even though it is git-ignored.

See [Testing](testing.md) for scenarios. See [Publishing](publishing.md) for releases.

---


# CI and GitHub Actions

The automation stack lives under `.github/workflows/`. A short overview is also in [`.github/workflows/README.md`](../../.github/workflows/README.md).

## Workflow files

| Workflow | Role |
|----------|------|
| **`cicd.yaml`** | **Orchestrator.** Defines event triggers (push, PR, `v*` tag, `workflow_dispatch`). Runs a `detect` job that sets flags from changed paths, then calls **`ci.yaml`** (reusable CI). For releases, calls **`cd.yaml`** when appropriate. |
| **`ci.yaml`** | **Reusable CI.** Lint, metadata validation, unit tests, feature scenario tests, macOS tests, dist tests. Callable on its own via `workflow_dispatch`. |
| **`cd.yaml`** | **Reusable CD.** Publishes features to GHCR and creates a GitHub Release. Callable via `workflow_dispatch` with a `tag` input (publish-only path). |
| **`devcontainer-image.yaml`** | Builds and publishes the repository devcontainer image (cache layers for CI/dev). |

## Path-based job selection (`detect`)

`detect` in `cicd.yaml` maps changed paths to jobs (simplified from `.github/workflows/README.md`):

| Changed path | Jobs triggered |
|--------------|----------------|
| `*.sh`, `*.bash`, `*.bats` | `lint` |
| `src/**/devcontainer-feature.json` | `validate` |
| `lib/**`, `test/unit/**` | `unit-native`, `unit-linux` |
| `src/<feature>/` or `test/<feature>/` | `test-features` (matrix), `test-macos` if macOS scenarios exist |
| `install-os-pkg` in changed list | `test-os-pkg` (multi-distro matrix) |
| `features/install.sh`, `features/sysset.sh`, `scripts/build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `test-dist-*` |

On `workflow_dispatch` or a `v*` tag push, **all** jobs run. **CD** runs only when the workflow decides it is a release (`is_release=true`) **and** CI succeeds.

## Manual runs

- Run full CI: **Actions → CI** (reusable workflow) or trigger via `gh workflow run` for your setup.
- Release with tests first: **CI/CD** workflow (`cicd.yaml`) with `tag` input.
- Publish without tests: **CD** workflow (`cd.yaml`) with `tag` input (see [Publishing](publishing.md)).

## Streaming logs locally

Use `just watch-gha --commit <sha>` or `just watch-gha --run <workflow-run-id>` to poll GitHub Actions and save logs under `.local/logs/gha/` (`just --list` / `justfile`).
