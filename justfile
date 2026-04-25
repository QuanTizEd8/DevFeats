# SysSet Developer Tasks.
#
# List recipes: `just --list`.
# Global: bash, strict mode.

set shell := ["bash", "-euo", "pipefail", "-c"]
py := "bash scripts/python.sh"


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



# ── Build ─────────────────────────────────────────────────────────────────────

[
  group('build'),
  doc('Regenerate git-ignored src/ from features/, lib/, bootstrap (JSON, deps, install.bash, _lib/, files/).')
]
sync:
    {{py}} scripts/sync-src.py


[
  group('build'),
  doc('Fail if src/ is stale or missing (no writes); same as scripts/sync-src.py --check.')
]
sync-check:
    {{py}} scripts/sync-src.py --check


[
  group('build'),
  doc('Build dist/ release artifacts; pass args directly to scripts/build-artifacts.sh (e.g. just build-dist v1.2.3); runs sync first.')
]
build-dist *args: sync
    bash scripts/build-artifacts.sh {{args}}


[
  group('build'),
  doc('Preview which features need a new GitHub Release (queries GitHub API). Extra args pass through to scripts/detect-releasable.py.')
]
detect-releasable *args:
    {{py}} scripts/detect-releasable.py --repo quantized8/sysset {{args}}


[
  group('build'),
  doc('Preview next bundle tag/notes/manifest. Pass args directly to scripts/compute-bundle-tag.py (e.g. --notes-body, --manifest, --repo owner/name).')
]
compute-bundle-tag *args:
    {{py}} scripts/compute-bundle-tag.py --repo quantized8/sysset {{args}}


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
    {{py}} -m unittest discover -s test/scripts -t test/scripts -v


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
    {{py}} scripts/gen_docs.py


[
  group('docs'),
  doc('CI: exit non-zero if gen-docs would modify tracked files.')
]
gen-docs-check:
    {{py}} scripts/gen_docs.py --check


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
  doc('Watch GHA via scripts/watch-gha-run.sh; pass args through directly (e.g. just watch-gha --run <id> or just watch-gha --commit <sha>). Logs in .local/logs/gha/.')
]
watch-gha *args:
    bash scripts/watch-gha-run.sh {{args}}
