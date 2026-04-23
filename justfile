# SysSet Developer Tasks.
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
    if [[ $# -gt 0 ]]; then
      echo "$@" | xargs -P"${ncpu}" -n8 shellcheck
    else
      [[ -d src ]] || just sync
      { git ls-files -- '*.sh' '*.bash' | grep -v '^features/[^/]*/install\.bash$'
        find src -maxdepth 2 -name 'install.bash' 2>/dev/null
      } | sort -u | xargs -P"${ncpu}" -n8 shellcheck
    fi


[
  group('code-quality'),
  doc('Validate features/*/metadata.yaml against metadata.schema.json.')
]
validate-metadata:
    #!/usr/bin/env bash
    set -euo pipefail
    python scripts/validate-metadata.py


# ── Build ─────────────────────────────────────────────────────────────────────

[
  group('build'),
  doc('Regenerate git-ignored src/ from features/, lib/, bootstrap (JSON, deps, install.bash, _lib/, files/).')
]
sync:
    bash scripts/sync-src.sh


[
  group('build'),
  doc('Fail if src/ is stale or missing (no writes); same as scripts/sync-src.sh --check.')
]
sync-check:
    bash scripts/sync-src.sh --check


[
  group('build'),
  doc('Build dist/ release artifacts; optional version e.g. just build-dist v1.2.3; runs sync first.')
]
build-dist version="": sync
    bash scripts/build-artifacts.sh {{version}}


[
  group('build'),
  doc('Preview which features need a new GitHub Release (queries the GitHub API).')
]
detect-releasable repo="quantized8/sysset":
    python3 scripts/detect-releasable.py --repo {{repo}}


[
  group('build'),
  doc('Preview the next bundle tag, release notes, or manifest (modes: default|notes|manifest).')
]
compute-bundle-tag mode="default" repo="quantized8/sysset":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{mode}}" in
      default) python3 scripts/compute-bundle-tag.py --repo {{repo}} ;;
      notes)   python3 scripts/compute-bundle-tag.py --repo {{repo}} --notes-body ;;
      manifest) python3 scripts/compute-bundle-tag.py --repo {{repo}} --manifest ;;
      *) echo "mode must be one of: default|notes|manifest" >&2; exit 1 ;;
    esac


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
    #!/usr/bin/env bash
    set -euo pipefail
    python3 -m unittest discover -s test/scripts -t test/scripts -v


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
    python3 scripts/gen_docs.py


[
  group('docs'),
  doc('CI: exit non-zero if gen-docs would modify tracked files.')
]
gen-docs-check:
    python3 scripts/gen_docs.py --check


[
  group('docs'),
  doc('Build Sphinx site to docs/.build/ (conda env sysset-website from docs/environment.yaml).')
]
build-website:
    conda run -n sysset-website --no-capture-output \
      python -m sphinx -b dirhtml docs docs/.build \
      --keep-going --color --jobs auto


[
  group('docs'),
  doc('Live-rebuild Sphinx with browser preview (same conda env as docs).')
]
build-website-live:
    conda run -n sysset-website --no-capture-output \
      python -m sphinx_autobuild docs docs/.build \
      -b dirhtml --open-browser --watch docs


# ── Dev tooling ───────────────────────────────────────────────────────────────

[
  group('dev'),
  doc('Watch GHA: set run=<id> OR commit=<sha/ref>; optional log_base=<dir>; logs in .local/logs/gha/; else use scripts/watch-gha-run.sh.')
]
watch-gha run="" commit="" log_base="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{run}}" && -n "{{commit}}" ]]; then
      echo "Error: set only one of run or commit." >&2
      exit 1
    fi
    args=()
    [[ -n "{{log_base}}" ]] && args+=(--log-base "{{log_base}}")
    if [[ -n "{{run}}" ]]; then
      bash scripts/watch-gha-run.sh "${args[@]}" --run "{{run}}"
    elif [[ -n "{{commit}}" ]]; then
      bash scripts/watch-gha-run.sh "${args[@]}" --commit "{{commit}}"
    else
      echo "Usage: just watch-gha run=<id>  OR  just watch-gha commit=<sha>" >&2
      echo "       Optional: log_base=<dir>" >&2
      exit 1
    fi
