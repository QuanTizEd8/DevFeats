# DevFeats Developer Tasks.
#
# List recipes: `just --list`.
# Global: bash, strict mode.
#
# ── Invocation patterns ───────────────────────────────────────────────────────
#
#   pixi run [--environment ENV] <task>   all pixi-managed tools (proman, ruff, sphinx)
#   bash .dev/scripts/CATEGORY/SCRIPT.sh  system-level ops (Docker, bats, streaming)
#
# ── Naming convention ─────────────────────────────────────────────────────────
#
#   <type>-<domain>[-<modifier>]
#
#   Types:   sync · build · lint · format · test · fetch · show · release · run
#   Domains: sh · py · src · feats · lib · docs · gha
#   Modifiers: check (verify-only) · live (file-watch) · pkg · env · envs · mod · macos
#
#   Bare name = apply/write; -check variant = verify-only (no writes).
#   Composite tasks (no domain) run every subdomain variant: lint, format, test.

set shell := ["bash", "-euo", "pipefail", "-c"]


# ── Format ────────────────────────────────────────────────────────────────────

[
  group('format'),
  doc('Format shell files with shfmt (whole tree or pass paths; respects .editorconfig ignores).')
]
format-sh *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ $# -gt 0 ]]; then
      shfmt --write "$@"
    else
      shfmt --write --apply-ignore .
    fi


[
  group('format'),
  doc('Check shell files formatting without writing (CI-style); pass paths to limit scope.')
]
format-sh-check *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ $# -gt 0 ]]; then
      shfmt --diff "$@"
    else
      shfmt --diff --apply-ignore .
    fi


[
  group('format'),
  doc('Format Python files with ruff.')
]
format-py *files:
    pixi run --environment lint format-py {{ if files != "" { '"' + files + '"' } else { "" } }}


[
  group('format'),
  doc('Check Python formatting with ruff (CI-style, no writes).')
]
format-py-check:
    pixi run --environment lint format-py-check


[
  group('format'),
  doc('Format all files: shell + Python.')
]
format: format-sh format-py


[
  group('format'),
  doc('Check formatting of all files without writing.')
]
format-check: format-sh-check format-py-check


# ── Lint ──────────────────────────────────────────────────────────────────────

[
  group('lint'),
  doc('Shellcheck tracked shell and assembled src/*/install.bash; no args runs sync-src if src/ missing; pass paths to limit.')
]
lint-sh-check *files:
    #!/usr/bin/env bash
    set -euo pipefail
    ncpu=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)
    # shellcheck with external-sources can be memory-heavy on large files.
    # Use conservative parallelism by default to avoid OOM kills (exit 137)
    # in CI and local runs; allow override when needed.
    jobs="${LINT_JOBS:-2}"
    if [[ ! "$jobs" =~ ^[0-9]+$ || "$jobs" -lt 1 ]]; then
      jobs=2
    fi
    ((jobs > ncpu)) && jobs="$ncpu"
    batch="${LINT_BATCH:-2}"
    if [[ ! "$batch" =~ ^[0-9]+$ || "$batch" -lt 1 ]]; then
      batch=2
    fi
    if [[ $# -gt 0 ]]; then
      echo "$@" | xargs -P"${jobs}" -n"${batch}" shellcheck
    else
      [[ -d src ]] || just sync-src
      { git ls-files -- '*.sh' '*.bash' | grep -v '^features/[^/]*/install\.bash$'
        find src -maxdepth 2 -name 'install.bash' 2>/dev/null
      } | sort -u | xargs -P"${jobs}" -n"${batch}" shellcheck
    fi


[
  group('lint'),
  doc('Check Python files with ruff (no fixes).')
]
lint-py-check:
    pixi run --environment lint lint-py-check


[
  group('lint'),
  doc('Lint and fix Python files with ruff.')
]
lint-py *files:
    pixi run --environment lint lint-py {{ if files != "" { '"' + files + '"' } else { "" } }}


[
  group('lint'),
  doc('Run all linters: shell + Python (check only, no writes).')
]
lint: lint-sh-check lint-py-check


# ── Sync ──────────────────────────────────────────────────────────────────────

[
  group('sync'),
  doc('Regenerate git-ignored src/ from features/, lib/, bootstrap (JSON, deps, install.bash, _lib/, files/).')
]
sync-src:
    pixi run sync-src


[
  group('sync'),
  doc('Fail if src/ is stale or missing (no writes); same as proman-sync --check.')
]
sync-src-check:
    pixi run sync-src-check


[
  group('sync'),
  doc('Regenerate injected doc markers (lib API tables in writing-features and lib.instructions).')
]
sync-docs:
    pixi run sync-docs


[
  group('sync'),
  doc('CI: exit non-zero if sync-docs would modify tracked files.')
]
sync-docs-check:
    pixi run sync-docs-check


# ── Build ─────────────────────────────────────────────────────────────────────

[
  group('build'),
  doc('Build dist/ release artifacts; pass args directly to proman-build-feats (e.g. just build-feats v1.2.3); runs sync-src first.')
]
build-feats *args: sync-src
    pixi run build-feats {{args}}


[
  group('build'),
  doc('Build Sphinx docs site to .local/build/docs/.')
]
build-docs:
    pixi run build-docs


[
  group('build'),
  doc('Live-rebuild Sphinx with browser preview.')
]
build-docs-live:
    pixi run build-docs-live


[
  group('build'),
  doc('Package .local/build/docs/ into a GitHub Pages artifact tarball.')
]
build-docs-pkg: build-docs
    pixi run build-docs-pkg


# ── Test ──────────────────────────────────────────────────────────────────────

[
  group('test'),
  doc('Run all bats unit tests for lib/ (git submodule init for test/lib/bats required).')
]
test-lib:
    bash .dev/scripts/test/run-unit.sh


[
  group('test'),
  doc('Run unit tests for one lib module e.g. just test-lib-mod ospkg.')
]
test-lib-mod module:
    bash .dev/scripts/test/run-unit.sh --module {{module}}


[
  group('test'),
  doc('Run lib/ unit tests in one container environment e.g. just test-lib-env alpine-3.20.')
]
test-lib-env env *args:
    pixi run --environment test test-lib-env {{env}} {{args}}


[
  group('test'),
  doc('Run lib/ unit tests in all container environments (requires docker).')
]
test-lib-envs *args:
    pixi run --environment test test-lib-envs {{args}}


[
  group('test'),
  doc('Run Python unit tests for proman/ (pytest).')
]
test-py:
    pixi run --environment test test-py


[
  group('test'),
  doc('Run scenario and fail tests for one feature e.g. just test-feats install-pixi.')
]
test-feats feat *args:
    pixi run --environment test test-feats {{feat}} {{args}}


[
  group('test'),
  doc('Run macOS scenarios for a feature natively e.g. just test-feats-macos install-pixi.')
]
test-feats-macos feat *args:
    pixi run --environment test test-feats {{feat}} --mode macos {{args}}


[
  group('test'),
  doc('Run all local test suites: lib (native) + Python + features. Requires docker.')
]
test:
    #!/usr/bin/env bash
    set -euo pipefail
    _rc=0
    just test-lib  || _rc=1
    just test-py   || _rc=1
    just test-feats || _rc=1
    exit "$_rc"


# ── Release ───────────────────────────────────────────────────────────────────

[
  group('release'),
  doc('Preview which features need a new GitHub Release (queries GitHub API). Extra args pass through to proman-release-detect.')
]
release-detect *args:
    pixi run release-detect {{args}}


# ── Show ──────────────────────────────────────────────────────────────────────

[
  group('show'),
  doc('Print a list of all features and their descriptions.')
]
show-feats:
    pixi run show-feats


[
  group('show'),
  doc('Print a list of all feature options and their number of occurrences across all features.')
]
show-feat-opts:
    pixi run show-feat-opts


[
  group('show'),
  doc('Print one value from .config/<file>.yaml (yq path). Example: just show-config ci image.suffix')
]
show-config file key:
    bash .dev/scripts/show/config.sh {{file}} {{key}}


# ── Fetch ─────────────────────────────────────────────────────────────────────

[
  group('fetch'),
  doc('Fetch GHA workflow run logs; pass args through directly (e.g. just fetch-gha --run <id> or just fetch-gha --commit <sha>). Logs in .local/logs/gha/.')
]
fetch-gha *args:
    bash .dev/scripts/fetch/gha.sh {{args}}


# ── Internal ──────────────────────────────────────────────────────────────────

[
  private,
  doc('Run any command inside a Docker-in-Docker environment (GHA CI use only).')
]
run-gha-dind *args:
    bash .dev/scripts/ci/gha-dind.sh {{args}}
