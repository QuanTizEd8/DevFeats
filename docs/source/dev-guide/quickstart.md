# Quickstart Guide

## Development Environment

The project ships a ready-to-use Dev Container at `.devcontainer/.dev/`, which encapsulates the full development environment for the project. It installs all necessary tools for development, testing, and documentation, ensuring a consistent setup across different machines and operating systems. You can use this Dev Container in [VS Code](https://code.visualstudio.com/docs/devcontainers/containers), [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/adding-a-dev-container-configuration/introduction-to-dev-containers), or any other [supporting tool](https://containers.dev/supporting) that adheres to the [Development Container Specification](https://containers.dev/implementors/spec/); simply open your local clone of the repository in the Dev Container to get started.



### Git Hooks

The project uses [Lefthook](https://github.com/evilmartians/lefthook) to manage Git hooks.
The dev container runs `lefthook install` on create, so hook definitions in [`lefthook.yml`](../lefthook.yml) are registered.


### Task Runner

The project uses [just](https://github.com/casey/just) as its task runner; all routine project tasks (e.g. format, lint, test, build) are implemented as `just` recipes.


Run `just --list` to see all available commands and their descriptions in the `justfile`. Recipes are grouped by category (e.g. testing, CI, publishing) and include comments with additional details.


### CI

The automation stack lives under `.github/workflows/`.

Lint (shfmt + shellcheck) runs as part of the reusable **`ci.yaml`** workflow when the change set triggers the `lint` job (see [CI](ci.md)). Locally, use `just format-check` and `just lint`.

`shfmt --apply-ignore` respects `.editorconfig` / ignore rules so generated paths under `src/` are not formatted as hand-written sources.


## Workspace

The workspace is a git repository with the following key files and directories:

:`.config/`:
    Project configuration files under `.config/proman/` (`_main.yaml`, `ci.yaml`, `docs.yaml`, read by proman), plus `ruff.toml` and `pytest.ini` for Python tooling.

:`.dev/`:
    [Development workflows](/dev-guide/devops/dev) — local libraries and scripts for build, sync, validation, and other development routines.

:`.devcontainer/`:
    Dev Container configuration files for the project's [development environment](/dev-guide/environment), as well as auto-generated Dev Container configuration files for [live testing](/dev-guide/tests/live) local and released features.

:`.github/`:
    GitHub configuration files, including GitHub Actions [CI/CD pipelines](/dev-guide/devops/ops), and GitHub [Copilot customizations](/dev-guide/devops/ai).

:`.local/`:
    Git-ignored directory for temporary files like logs, build and test artifacts, scratch files, etc. Used for short-term storage during local development.

:`docs/`:
    Project [documentation](/dev-guide/docs) source files and website configuration.

:`features/`:
    [Feature](/dev-guide/features) source files, including metadata, installation scripts, and feature-specific user and developer documentation.

:`lib/`:
    [Shared library](/dev-guide/features/lib) source files, containing helper functions used by feature scripts.

:`test/`:
    [Tests](/dev-guide/tests) for features, the shared library, and local development workflows.

:`justfile`:
    Developer recipes — run `just --list` to see available tasks for common development routines.

:`.editorconfig`:
    shfmt style config (2-space, case-indent, etc.).

:`.shellcheckrc`:
    shellcheck defaults (shell=bash, external-sources=true).

:`lefthook.yml`:
    Lefthook configuration.


:::{admonition} Read-only directories
:class: danger

The following files and directories should **never be edited**; they are either fully auto-generated, git-ignored, symbolic links, or external dependencies:

:`.devcontainer/**/!(.dev)/**`:
    Other than the `.devcontainer/.dev/` directory, all files in `.devcontainer/` are either fully auto-generated (`.devcontainer/try-*/**` and `.devcontainer/test-*/**`) or symlinks (`.devcontainer/.src/`) for [live testing](/dev-guide/tests/live) of features in dev containers.

:`docs/source/features/`:
    Auto-generated directory for [feature documentation](/dev-guide/docs/features) generated from `features/` metadata and notes. The source of truth for feature documentation is the `metadata.yaml` and `NOTES.md` files in each `features/<id>/` directory.

:`docs/source/library/`:
    Auto-generated directory for [library documentation](/dev-guide/docs/library) generated from `lib/` source files. The source of truth for library documentation is the docstrings in the source code.

:`src/`:
    [Feature Output](/dev-guide/features/src) — publication-ready feature scripts generated from `features/` and `lib/`.

:`test/lib/bats/`:
    [Bats Testing Framework](/dev-guide/tests/unit) — Git submodule containing the Bats testing framework for unit tests.

:::







## Common commands

Run **`just --list`** for the full recipe list. Typical workflow:

```sh
just sync-src                    # regenerate src/ (or: python3 scripts/sync-src.py)
just format && just lint     # format + shellcheck
just test-feats install-pixi
just test-lib
just fetch-gha --commit HEAD # after push — stream CI logs
```


Run `just --list` for the full recipe list with descriptions. Key workflows:

```sh
# Regenerate src/ from features/ + lib/ + install.sh
just sync-src

# Format shell files in-place, then run shellcheck
just format && just lint

# Format-check only (CI-style, no writes) + lint
just format-check && just lint

# Validate metadata files and check src/ is up-to-date
just sync-src-check

# Run feature scenario tests for one feature (requires Docker + devcontainer CLI)
just test-feats install-pixi

# Run shared library unit tests (no Docker needed)
just test-lib

# Build the docs website locally (HTML under .local/build/docs/; requires pixi docs env)
just build-docs

# Serve docs with live reload (same output directory)
just build-docs-live

# Watch GitHub Actions logs after a push
just fetch-gha --commit HEAD
```

Preview what the next CD run will do without pushing:

```sh
just release-detect           # print features_to_release JSON
just compute-bundle-tag          # print the next bundle version decision
just compute-bundle-tag notes    # print the release notes markdown
just compute-bundle-tag manifest # print the bundle manifest YAML
```




# Shell code style

All shell scripts are formatted with **shfmt** and linted with **shellcheck**.

- Style is defined in `.editorconfig`: 2-space indent, `switch_case_indent = true`, `function_next_line = false` (brace on same line), `space_redirects = true`.
- `.shellcheckrc` sets `shell=bash` and `external-sources=true` globally.
- Run `just format` to auto-format; `just format-check` for a CI-style check (no writes); `just lint` for shellcheck.
- `*.bats` files use `shell_variant = bats` in `.editorconfig` and are formatted by shfmt.
- `shfmt --apply-ignore` (used by `just format` / `just format-check` on the full tree) excludes generated paths via `.editorconfig` ignore rules.
- `features/*/install.bash` are **body-only** (no autogenerated header). Linting targets the assembled `src/*/install.bash` files. Run `python3 scripts/sync-src.py` (or `just sync-src`) before `just lint` when `src/` is missing or stale.
- **Shared library**: Prefer `lib/` helpers over duplicating logic. See `docs/dev-guide/writing-features.md` for the full API.
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
just sync-src            # regenerate _lib/ copies and install.sh stubs
```

VS Code users get formatting automatically via the
`foxundermoon.shell-format` extension (format on save) and inline lint
diagnostics via `timonwong.shellcheck`. Recommended extensions are listed in
`.vscode/extensions.json` and will be suggested when you open the repo.


