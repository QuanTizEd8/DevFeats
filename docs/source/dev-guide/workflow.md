# Workflow

The automation stack lives under `.github/workflows/`.


## Common commands

Run **`just --list`** for the full recipe list. Typical workflow:

```sh
just sync                    # regenerate src/ (or: python3 scripts/sync-src.py)
just format && just lint     # format + shellcheck
just test-feature install-pixi
just test-unit
just watch-gha --commit HEAD # after push — stream CI logs
```


Run `just --list` for the full recipe list with descriptions. Key workflows:

```sh
# Regenerate src/ from features/ + lib/ + bootstrap.sh
just sync

# Format shell files in-place, then run shellcheck
just format && just lint

# Format-check only (CI-style, no writes) + lint
just format-check && just lint

# Validate metadata files and check src/ is up-to-date
just sync-check

# Run feature scenario tests for one feature (requires Docker + devcontainer CLI)
just test-feature install-pixi

# Run shared library unit tests (no Docker needed)
just test-unit

# Build the docs website locally (requires sysset-website conda env)
just build-website

# Serve docs with live reload
just build-website-live

# Watch GitHub Actions logs after a push
just watch-gha --commit HEAD
```

Preview what the next CD run will do without pushing:

```sh
just detect-releasable           # print features_to_release JSON
just compute-bundle-tag          # print the next bundle version decision
just compute-bundle-tag notes    # print the release notes markdown
just compute-bundle-tag manifest # print the bundle manifest YAML
```



---

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










# Publishing Features

This guide covers how to version, publish, and make features discoverable
once they are ready for release.


## Versioning

Each feature is versioned **independently** via the `version` field in its `metadata.yaml` (which is also copied to its generated `devcontainer-feature.json`). Versions follow [semver](https://semver.org) format (`X.Y.Z`). When making a change to a feature, bump the version according to the nature of the change:
- **Patch** (`X.Y.Z+1`) — backwards-compatible bug fixes and minor corrections with no behaviour change.
- **Minor** (`X.Y+1.0`) — backwards-compatible new options or capabilities.
- **Major** (`X+1.0.0`) — breaking changes to option names, defaults, or behaviour.

### Version-bump discipline (CI guard)

Because `lib/` is embedded into every feature tarball as `_lib/`, a change
in `lib/` semantically affects every feature's payload. A CI lint enforces
the following rule on pull requests:

> Any PR that touches `lib/`, `features/bootstrap.sh`, or a `features/<id>/`
> directory must bump the `version` in the corresponding `metadata.yaml`
> file(s). For `lib/` and `features/bootstrap.sh` changes, **every** feature
> that embeds the changed file must be bumped (in practice: all of them).

The guard is implemented in
[`.github/workflows/scripts/cicd_detect.py`](../../.github/workflows/scripts/cicd_detect.py)
and runs as part of the `detect` job in `cicd.yaml`. A failed check names
the features that need a bump.


## Release identity

Each feature has its own release identity:

- **Tag scheme:** `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`).
- **GitHub Release** per tag, shipping exactly one asset:
  `sysset-<feature-id>.tar.gz`.
- **GHCR tag** per version:
  `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>:<major>`, `:<major.minor>`, and
  `:<major.minor.patch>`.

Each CD run also produces an **accumulator-tagged bundle release**
(`v<X.Y.Z>`) whose assets are:

- `sysset-v<X.Y.Z>.tar.gz` — offline kit (installers, `manifest.json`, digest-keyed `features/`) for manual/offline transfer. Installer runtime resolution is OCI per-feature and does not consume bundle pinning.

The bundle's global semver is derived from the highest per-feature bump in
the run; see [Bundle accumulator](#bundle-accumulator) below.


## Publishing via GitHub Actions

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
   - Runs `gh release create "<feature>/<X.Y.Z>" sysset-<feature>.tar.gz
     --title "<feature> <X.Y.Z>" --generate-notes`.
3. **`publish-bundle`** (`needs: [publish-ghcr, publish-gh-release]`) —
   runs [`scripts/compute-bundle-tag.py`](../../scripts/compute-bundle-tag.py)
   to compute the next `v<X.Y.Z>`, produce `notes.md`, emit a JSON manifest
   base, and run `scripts/build-offline-kit.sh` to produce
   `sysset-v<X.Y.Z>.tar.gz`. Creates the tag, then
   `gh release create "v<X.Y.Z>" sysset-v<X.Y.Z>.tar.gz
   --latest --notes-file notes.md`. Skips cleanly when the aggregate bump
   is `none` (idempotent re-runs).

The per-feature and bundle artefacts all come from the same `sysset-dist`
CI artefact built once in `ci.yaml`'s `prepare` step — no `gh release
download` round-trip. The
[version-bump guard](#version-bump-discipline-ci-guard) guarantees that a
feature whose `metadata.yaml` version is unchanged on this commit has
identical payload to its already-published release. The offline kit tarball is
assembled from those same per-feature `dist/*.tar.gz` files via `scripts/build-offline-kit.sh`.


### Manual single-feature publish (`workflow_dispatch`)

For hotfixes or a re-deploy after manual verification, trigger `cicd.yaml`
with the `feature` + `version` inputs:

```bash
gh workflow run "CI/CD" --field feature=install-pixi --field version=1.2.3
```

This bypasses `detect-releasable.py` and queues exactly one feature for
release. CI still runs first; CD publishes only if the tests pass. The
bundle job then runs as usual (recomputing the next bundle tag from the
single bump).

Or open the **Actions** tab in GitHub, select **CI/CD**, and click **Run
workflow**.


### Local preview

Before pushing, preview what the next CD run will do:

```bash
just detect-releasable            # prints the features_to_release JSON
just compute-bundle-tag           # prints the JSON decision record
just compute-bundle-tag notes     # prints the release-notes markdown
just compute-bundle-tag manifest  # prints the bundle manifest JSON base
```





## References

- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/action — GitHub Action for publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [devcontainers/devcontainers.github.io — collection-index.yml](https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/_data/collection-index.yml)
- [Dev Containers — Feature versioning](https://containers.dev/implementors/features/#versioning)
- [GitHub Container Registry — managing package visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)












# Shell code style

All shell scripts are formatted with **shfmt** and linted with **shellcheck**.

- Style is defined in `.editorconfig`: 2-space indent, `switch_case_indent = true`, `function_next_line = false` (brace on same line), `space_redirects = true`.
- `.shellcheckrc` sets `shell=bash` and `external-sources=true` globally.
- Run `just format` to auto-format; `just format-check` for a CI-style check (no writes); `just lint` for shellcheck.
- `*.bats` files use `shell_variant = bats` in `.editorconfig` and are formatted by shfmt.
- `shfmt --apply-ignore` (used by `just format` / `just format-check` on the full tree) excludes generated paths via `.editorconfig` ignore rules.
- `features/*/install.bash` are **body-only** (no autogenerated header). Linting targets the assembled `src/*/install.bash` files. Run `python3 scripts/sync-src.py` (or `just sync`) before `just lint` when `src/` is missing or stale.
- **Shared library**: Prefer `lib/` helpers over duplicating logic. See `docs/dev-guide/writing-features.md` for the full API (tables are also injected into `.github/instructions/lib.instructions.md` via `just gen-docs`).
- **Logging**: Use `logging__error`, `logging__warn`, `logging__info`, `logging__success`, `logging__debug`, and phase helpers (`logging__install`, `logging__download`, …) from `lib/logging.sh` instead of ad hoc `echo "…" >&2`. Shared option `log_level` controls verbosity (`silent|error|warn|info|debug|trace`); generated installers call `logging__set_level` after parsing, and `trace` enables `set -x`.

CI runs the reusable **`ci.yaml`** workflow (invoked from **`cicd.yaml`**), which includes shfmt and shellcheck when the change set warrants it. See `docs/dev-guide/ci.md`.



## Code style — `shfmt` and `shellcheck`

All shell scripts in this repository are formatted with
[shfmt](https://github.com/mvdan/sh) and linted with
[shellcheck](https://www.shellcheck.net/).

### Style configuration

`.editorconfig` is the single source of truth for shfmt style. The key
settings for `*.sh` and `*.bats` files:

| Setting | Value | Effect |
|---|---|---|
| `indent_size` | `2` | Two-space indentation |
| `switch_case_indent` | `true` | Case branches indented inside `case` blocks |
| `function_next_line` | `false` | Opening brace on the same line as `fn() {` |
| `space_redirects` | `true` | Space between redirect operator and target |
| `binary_next_line` | `false` | `&&` / `\|\|` at end of line (not start) |

`*.bats` uses `shell_variant = bats` so shfmt applies bats-aware parsing.

### Shellcheck configuration

`.shellcheckrc` sets global defaults:

```ini
shell=bash          # default dialect for files without a shebang
external-sources=true   # follow source/. directives
```

Per-file or per-line overrides use inline directives:

```bash
# shellcheck disable=SC2034
```

### Developer workflow

The [justfile](../../justfile) provides convenience recipes:

```bash
just format          # auto-format all shell files in place (shfmt -w)
just format-check    # check formatting without writing (used in CI)
just lint            # run shellcheck on all tracked .sh/.bash files
just sync            # regenerate _lib/ copies and install.sh stubs
```

VS Code users get formatting automatically via the
`foxundermoon.shell-format` extension (format on save) and inline lint
diagnostics via `timonwong.shellcheck`. Recommended extensions are listed in
`.vscode/extensions.json` and will be suggested when you open the repo.

### CI enforcement

Lint (shfmt + shellcheck) runs as part of the reusable **`ci.yaml`** workflow when the change set triggers the `lint` job (see [CI](ci.md)). Locally, use `just format-check` and `just lint`.

`shfmt --apply-ignore` respects `.editorconfig` / ignore rules so generated paths under `src/` are not formatted as hand-written sources.





### Lefthook (optional)

[Lefthook](https://github.com/evilmartians/lefthook) is configured in `lefthook.yml`.

The devcontainer runs `lefthook install` on create so hooks are ready if you enable them. For shell style and CI behavior, see [`docs/snippets/code-style.md`](../snippets/code-style.md) and [CI](ci.md).

