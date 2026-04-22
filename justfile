# Global shell settings: all recipes run under bash with strict error handling.
set shell := ["bash", "-euo", "pipefail", "-c"]

# ── Code quality ──────────────────────────────────────────────────────────────

# Apply shfmt formatting to all tracked shell files. Pass files as arguments to
# format specific files only (used by lefthook). No-op if shfmt is not on PATH.
# test/unit/bats/** is excluded via .editorconfig ignore = true.
[group('code-quality')]
format *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shfmt > /dev/null 2>&1; then
      echo "ℹ️  shfmt not found — skipping format."
      exit 0
    fi
    if [[ $# -gt 0 ]]; then
      shfmt -w "$@"
    else
      shfmt -w --apply-ignore .
    fi

# Check formatting without writing — exits non-zero if any file differs.
# Used in CI. Pass files as arguments to check specific files only (used by lefthook).
# No-op if shfmt is not on PATH.
[group('code-quality')]
format-check *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shfmt > /dev/null 2>&1; then
      echo "ℹ️  shfmt not found — skipping format-check."
      exit 0
    fi
    if [[ $# -gt 0 ]]; then
      shfmt -d "$@"
    else
      shfmt -d --apply-ignore .
    fi

# Run shellcheck on all tracked shell files. Pass files as arguments to check
# specific files only (used by lefthook). No-op if shellcheck is not on PATH.
# features/*/install.bash are body-only; lint the assembled src/ copies.
# The full (no args) target auto-syncs src/ if absent, matching CI behaviour.
[group('code-quality')]
lint *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shellcheck > /dev/null 2>&1; then
      echo "ℹ️  shellcheck not found — skipping lint."
      exit 0
    fi
    ncpu=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)
    if [[ $# -gt 0 ]]; then
      echo "$@" | xargs -P"${ncpu}" -n8 shellcheck
    else
      [[ -d src ]] || bash scripts/sync-src.sh
      { git ls-files -- '*.sh' '*.bash' | grep -v '^features/[^/]*/install\.bash$'
        find src -maxdepth 2 -name 'install.bash' 2>/dev/null
      } | sort -u | xargs -P"${ncpu}" -n8 shellcheck
    fi

# Validate all features/*/metadata.yaml against features/metadata.schema.json.
# No-op if jsonschema is not importable.
[group('code-quality')]
validate-metadata:
    #!/usr/bin/env bash
    set -euo pipefail
    if python3 -c "import jsonschema, yaml" > /dev/null 2>&1; then
      python3 scripts/validate-metadata.py
    elif python -c "import jsonschema, yaml" > /dev/null 2>&1; then
      python scripts/validate-metadata.py
    else
      echo "ℹ️  jsonschema not found — skipping metadata validation. Install with: bash .devcontainer/setup-dev.sh --tools jsonschema"
    fi

# ── Build ─────────────────────────────────────────────────────────────────────

# Sync generated artifacts from canonical sources (features/ + lib/ → src/).
#   features/*/metadata.yaml  → src/*/devcontainer-feature.json
#   features/*/metadata.yaml  → src/*/dependencies/*.yaml
#   features/*/install.bash   → src/*/install.bash (header prepended)
#   lib/                      → src/*/_lib/
#   features/bootstrap.sh     → src/*/install.sh
[group('build')]
sync:
    bash scripts/sync-src.sh

# Verify all generated artifacts are up to date (CI-style, no writes).
# Exits non-zero if any file is missing or stale.
[group('build')]
sync-check:
    bash scripts/sync-src.sh --check

# Build standalone distribution artifacts into dist/.
# Runs sync first to ensure src/ is up to date.
[group('build')]
artifacts version="": sync
    bash scripts/build-artifacts.sh {{version}}

# ── Testing ───────────────────────────────────────────────────────────────────

# Run lib/ unit tests via bats-core (requires git submodules to be initialised).
[group('testing')]
test-unit:
    bash test/run-unit.sh

# ── Docs ─────────────────────────────────────────────────────────────────────

# Inject auto-generated content (lib API tables, JSON options blocks) into docs.
[group('docs')]
gen-docs:
    python3 scripts/gen_docs.py

# Dry-run: exits non-zero if any doc file would be changed by gen-docs. Used in CI.
[group('docs')]
gen-docs-check:
    python3 scripts/gen_docs.py --check

# Build the Sphinx documentation into docs/.build/.
# Requires the sysset-website conda environment (docs/environment.yaml).
[group('docs')]
docs:
    conda run -n sysset-website --no-capture-output \
      python -m sphinx -b dirhtml docs docs/.build \
      --keep-going --color --jobs auto

# Live-preview the docs with auto-rebuild on file changes.
# Requires the sysset-website conda environment (docs/environment.yaml).
[group('docs')]
docs-serve:
    conda run -n sysset-website --no-capture-output \
      python -m sphinx_autobuild docs docs/.build \
      -b dirhtml --open-browser --watch docs

# ── Dev tooling ───────────────────────────────────────────────────────────────

# Install all development tools required to work on this repo (idempotent).
[group('dev')]
install-dev:
    bash .devcontainer/setup-dev.sh

# Poll GitHub Actions and stream logs to .local/logs/gha/<sha>/<run-id>/.
# Provide exactly one of: run (workflow run ID) or commit (SHA or ref).
# Optional: log_base overrides the default log root directory.
# Examples:
#   just watch-gha run=12345678901
#   just watch-gha run=12345678901 log_base=/tmp/my-gha-logs
#   just watch-gha commit=main
#   just watch-gha commit=abc1234 log_base=/tmp/my-gha-logs
# For options not covered here, call scripts/watch-gha-run.sh directly.
[group('dev')]
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
