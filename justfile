# DevFeats Developer Tasks.
#
# List recipes: `just --list`.
# Global: bash, strict mode.

set shell := ["bash", "-euo", "pipefail", "-c"]


# ── Code quality ──────────────────────────────────────────────────────────────

[
  group('code-quality'),
  doc('Format shell files with shfmt (whole tree or pass paths; respects .editorconfig ignores).')
]
format *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ $# -gt 0 ]]; then
      shfmt -w "$@"
    else
      shfmt -w --apply-ignore .
    fi


[
  group('code-quality'),
  doc('Check shell files formatting without writing (CI-style); pass paths to limit scope.')
]
format-check *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ $# -gt 0 ]]; then
      shfmt -d "$@"
    else
      shfmt -d --apply-ignore .
    fi


[
  group('code-quality'),
  doc('Shellcheck tracked shell and assembled src/*/install.bash; no args runs sync if src/ missing; pass paths to limit.')
]
lint *files:
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
      [[ -d src ]] || just sync
      { git ls-files -- '*.sh' '*.bash' | grep -v '^features/[^/]*/install\.bash$'
        find src -maxdepth 2 -name 'install.bash' 2>/dev/null
      } | sort -u | xargs -P"${jobs}" -n"${batch}" shellcheck
    fi



# ── Build ─────────────────────────────────────────────────────────────────────

[
  group('build'),
  doc('Regenerate git-ignored src/ from features/, lib/, bootstrap (JSON, deps, install.bash, _lib/, files/).')
]
sync:
    pixi run sync


[
  group('build'),
  doc('Fail if src/ is stale or missing (no writes); same as .dev/scripts/build/sync-src.py --check.')
]
sync-check:
    pixi run sync-check


[
  group('build'),
  doc('Build dist/ release artifacts; pass args directly to .dev/scripts/build/build-artifacts.sh (e.g. just build-dist v1.2.3); runs sync first.')
]
build-dist *args: sync
    bash .dev/scripts/build/build-artifacts.sh {{args}}


[
  group('build'),
  doc('Preview which features need a new GitHub Release (queries GitHub API). Extra args pass through to .dev/scripts/release/detect-releasable.py.')
]
detect-releasable *args:
    pixi run python .dev/scripts/release/detect-releasable.py --repo quantized8/devfeats {{args}}


[
  group('build'),
  doc('Preview next bundle tag/notes/manifest JSON. Pass args to .dev/scripts/release/compute-bundle-tag.py (e.g. --notes-body, --manifest, --repo owner/name).')
]
compute-bundle-tag *args:
    pixi run python .dev/scripts/release/compute-bundle-tag.py --repo quantized8/devfeats {{args}}


# ── Testing ───────────────────────────────────────────────────────────────────

[
  group('testing'),
  doc('Run all bats unit tests for lib/ (git submodule init for test/unit/bats required).')
]
test-unit:
    bash test/run-unit.sh


[
  group('testing'),
  doc('Run Python unit tests for scripts/ (stdlib unittest; no extra deps beyond PyYAML).')
]
test-scripts:
    pixi run python -m unittest discover -s test/scripts -t test/scripts -v


[
  group('testing'),
  doc('Run unit tests for one lib module e.g. just test-module ospkg.')
]
test-module module:
    bash test/run-unit.sh --module {{module}}


[
  group('testing'),
  doc('Run scenario and fail tests for one feature e.g. just test-feature install-pixi.')
]
test-feature feat:
    bash test/run.sh feature {{feat}}


# ── Docs ─────────────────────────────────────────────────────────────────────

[
  group('docs'),
  doc('Regenerate injected doc markers (lib API tables in writing-features and lib.instructions).')
]
gen-docs:
    pixi run gen-docs


[
  group('docs'),
  doc('CI: exit non-zero if gen-docs would modify tracked files.')
]
gen-docs-check:
    pixi run gen-docs-check


[
  group('docs'),
  doc('Build Sphinx site to docs/.build/.')
]
build-website:
    pixi run build-website


[
  group('docs'),
  doc('Live-rebuild Sphinx with browser preview.')
]
build-website-live:
    pixi run build-website-live


# ── Dev tooling ───────────────────────────────────────────────────────────────

[
  group('dev'),
  doc('Watch GHA via .dev/scripts/ci/watch-gha-run.sh; pass args through directly (e.g. just watch-gha --run <id> or just watch-gha --commit <sha>). Logs in .local/logs/gha/.')
]
watch-gha *args:
    bash .dev/scripts/ci/watch-gha-run.sh {{args}}


[
  group('dev'),
  doc('Print a list of all features and their descriptions (from metadata.yaml).')
]
list-features:
    #!/usr/bin/env bash
    total=0
    for f in features/*/metadata.yaml; do
      name=$(basename "$(dirname "$f")")
      desc=$(yq -r '.description' "$f")
      printf '%s: %s\n' "$name" "$desc"
      total=$((total + 1))
    done
    printf 'Total features: %d\n' "$total"


[
  group('dev'),
  doc('Print a list of all feature options and their number of occurrences across all features.')
]
list-feature-options:
  yq -r '.options // {} | keys[]' features/*/metadata.yaml \
    | sort \
    | uniq -c \
    | sort -nr \
    | awk '{printf "%s (%d)\n", $2, $1}'
