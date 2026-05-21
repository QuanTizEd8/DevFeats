# Continuous Software Development (CI/CD)

The repository devcontainer image is built by `devcontainer.yaml` and used as the CI execution environment for `lint` and `validate` jobs. It is a multi-arch (amd64/arm64) image published to GHCR.

## Continuous Integration

The reusable **`ci.yaml`** contains these jobs (run conditionally based on `detect` output):

| Job | Runs on | What it does |
|-----|---------|-------------|
| `prepare` | Ubuntu | `just build-feats` → uploads `src/` and `dist/` as artifacts |
| `lint` | Devcontainer image | shfmt format-check + shellcheck on all shell files |
| `validate` | Devcontainer image | `devcontainers/action` validate-only on `./src` |
| `unit-native` | Ubuntu + macOS | bats unit suite for `lib/`; installs bash ≥ 4 on macOS first |
| `unit-linux` | debian, fedora, rockylinux, alpine containers | glibc/musl compatibility |
| `test-features` | DinD (Docker-in-Docker) | feature scenario tests matrix per feature |
| `test-macos` | `macos-latest` runner | native macOS scenario tests discovered from `test/<feature>/macos/` |
| `test-os-pkg` | Multiple distro containers | `install-os-pkg` dry-run matrix |
| `test-dist-*` | Various | dist suite tests |


### Change detection (`detect` job)

The `detect` job in `cicd.yaml` runs `python3 .github/workflows/scripts/cicd_detect.py`, which reads `.github/ci_trigger_paths.yaml`, diffs the changed files, and writes per-job run flags to `GITHUB_OUTPUT`. On `workflow_dispatch`, all flags are forced true regardless of the diff.

| Changed path(s) | CI jobs triggered |
|----------------|------------------|
| `*.sh`, `*.bash`, `*.bats` | `lint` |
| `src/**/devcontainer-feature.json` | `validate` |
| `lib/**`, `test/lib/**` | `unit-native`, `unit-linux` |
| `src/<feature>/` or `test/<feature>/` | `test-features` (matrix), `test-macos` if macOS scenarios exist |
| `install-os-pkg` in changed list | `test-os-pkg` (multi-distro matrix) |
| `features/install.sh`, `scripts/build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `test-dist-*` |

`cicd_detect.py` also enforces the **version-bump discipline** on pull requests: any PR that touches `lib/`, `features/install.sh`, or a `features/<id>/` directory must bump the corresponding `metadata.yaml` version. A failed check names the features that need a bump. See {doc}`publishing` for full versioning rules.

CD (`cd.yaml`) runs only when:
1. The push to `main` has at least one feature with an untagged version (determined by `scripts/detect-releasable.py` inside `cicd_detect.py`), **and**
2. CI passed.


### Manual triggers

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
just fetch-gha --commit <sha>
just fetch-gha --run <workflow-run-id>
```

Logs are saved under `.local/logs/gha/`.





## Continuous Deployment

Publication is driven by pushes to `main`. The
[`cicd.yaml`](../../.github/workflows/cicd.yaml) orchestrator runs the
[`detect`](../../.github/workflows/scripts/cicd_detect.py) step which calls
[`scripts/detect-releasable.py`](../../scripts/detect-releasable.py):

1. For every `features/<id>/metadata.yaml`, read `.version`.
2. Query GitHub for an existing release with `tag_name == "<id>/<version>"`.
3. If absent, the feature joins the `features_to_release` output.

If the list is non-empty, [`cd.yaml`](../../.github/workflows/cd.yaml)
runs with three jobs:

1. **`publish-ghcr`** — calls
   [`devcontainers/action`](https://github.com/devcontainers/action) with
   `publish-features: "true"` and `disable-repo-tagging: "true"`. The
   action pushes the OCI artefact to GHCR for every feature whose
   `metadata.yaml` version has not yet been published, idempotently
   skipping already-published versions. It no longer creates Git tags —
   our `publish-gh-release` job owns tagging.
2. **`publish-gh-release`** — matrix over `features_to_release`. For each
   entry:
   - Creates an annotated Git tag `<feature>/<X.Y.Z>` on `github.sha`.
   - Runs `gh release create "<feature>/<X.Y.Z>" devfeats-<feature>.tar.gz
     --title "<feature> <X.Y.Z>" --generate-notes`.
3. **`publish-bundle`** (`needs: [publish-ghcr, publish-gh-release]`) —
   runs [`scripts/compute-bundle-tag.py`](../../scripts/compute-bundle-tag.py)
   to compute the next `v<X.Y.Z>`, produce `notes.md`, emit a JSON manifest
   base, and run `scripts/build-offline-kit.sh` to produce
   `devfeats-v<X.Y.Z>.tar.gz`. Creates the tag, then
   `gh release create "v<X.Y.Z>" devfeats-v<X.Y.Z>.tar.gz
   --latest --notes-file notes.md`. Skips cleanly when the aggregate bump
   is `none` (idempotent re-runs).

The per-feature and bundle artefacts all come from the same `devfeats-dist`
CI artefact built once in `ci.yaml`'s `prepare` step — no `gh release
download` round-trip. The
[version-bump guard](#version-bump-discipline-ci-guard) guarantees that a
feature whose `metadata.yaml` version is unchanged on this commit has
identical payload to its already-published release. The offline kit tarball is
assembled from those same per-feature `dist/*.tar.gz` files via `scripts/build-offline-kit.sh`.

### Versioning

Each feature is versioned **independently** via the `version` field in its `metadata.yaml` (which is also copied to its generated `devcontainer-feature.json`). Versions follow [semver](https://semver.org) format (`X.Y.Z`). When making a change to a feature, bump the version according to the nature of the change:
- **Patch** (`X.Y.Z+1`) — backwards-compatible bug fixes and minor corrections with no behaviour change.
- **Minor** (`X.Y+1.0`) — backwards-compatible new options or capabilities.
- **Major** (`X+1.0.0`) — breaking changes to option names, defaults, or behaviour.

#### Version-bump discipline (CI guard)

Because `lib/` is embedded into every feature tarball as `_lib/`, a change
in `lib/` semantically affects every feature's payload. A CI lint enforces
the following rule on pull requests:

> Any PR that touches `lib/`, `features/install.sh`, or a `features/<id>/`
> directory must bump the `version` in the corresponding `metadata.yaml`
> file(s). For `lib/` and `features/install.sh` changes, **every** feature
> that embeds the changed file must be bumped (in practice: all of them).

The guard is implemented in
[`.github/workflows/scripts/cicd_detect.py`](../../.github/workflows/scripts/cicd_detect.py)
and runs as part of the `detect` job in `cicd.yaml`. A failed check names
the features that need a bump.

### Release identity

Each feature has its own release identity:

- **Tag scheme:** `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`).
- **GitHub Release** per tag, shipping exactly one asset:
  `devfeats-<feature-id>.tar.gz`.
- **GHCR tag** per version:
  `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>:<major>`, `:<major.minor>`, and
  `:<major.minor.patch>`.

### Local preview

Before pushing, preview what the next CD run will do:

```bash
just release-detect            # prints the features_to_release JSON
just compute-bundle-tag           # prints the JSON decision record
just compute-bundle-tag notes     # prints the release-notes markdown
just compute-bundle-tag manifest  # prints the bundle manifest JSON base
```

## References

- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/action — GitHub Action for publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [Dev Containers — Feature versioning](https://containers.dev/implementors/features/#versioning)


## devcontainer image

The `detect` job in `cicd.yaml` determines whether to rebuild the image or reuse the last published tag based on changes to `.devcontainer/` and the devcontainer definition files. This avoids unnecessary rebuilds while ensuring the CI image stays up to date.

