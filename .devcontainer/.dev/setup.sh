#!/usr/bin/env bash
# setup-dev.sh — Install development tools for sysset.
# Usage: bash .devcontainer/setup-dev.sh [--tools tool1,tool2,...]
#
# Available tools: pyyaml jsonschema shfmt shellcheck just devcontainers-cli lefthook
# Default (no --tools flag): install all tools.
#
# Designed to be idempotent — skips tools already installed at the required version.
# Works on macOS (Homebrew) and Debian/Ubuntu Linux (apt-get).
set -euo pipefail

# ── Parse --tools flag ─────────────────────────────────────────────────────────
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_ALL_TOOLS="pyyaml jsonschema shfmt shellcheck just devcontainers-cli lefthook"
_tools="${_ALL_TOOLS}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools)
      _tools="${2//,/ }"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── Detect OS ────────────────────────────────────────────────────────────────────────────────
_os="$(uname -s)"

# ── Helper: check if a command exists ──────────────────────────────────────────────────────────
_has() { command -v "$1" > /dev/null 2>&1; }

# ── pip flags (PEP 668: pass --break-system-packages when pip supports it) ──────────
_pip_flags=()
if python3 -m pip install --help 2> /dev/null | grep -q -- '--break-system-packages'; then
  _pip_flags+=(--break-system-packages)
fi

# ── Install functions ──────────────────────────────────────────────────────────

_install_pyyaml() {
  echo "▶ Installing PyYAML..." >&2
  python3 -m pip install "${_pip_flags[@]}" -r "${_SCRIPT_DIR}/requirements.txt"
  echo "✅ PyYAML installed." >&2
}

_install_jsonschema() {
  if python3 -c "import jsonschema" > /dev/null 2>&1; then
    echo "✅ jsonschema already installed — skipping." >&2
    return
  fi
  echo "▶ Installing jsonschema..." >&2
  python3 -m pip install "${_pip_flags[@]}" -r "${_SCRIPT_DIR}/requirements.txt"
  echo "✅ jsonschema installed." >&2
}

_install_lefthook() {
  if _has lefthook; then
    echo "✅ lefthook already installed — skipping." >&2
    return
  fi
  echo "▶ Installing lefthook..." >&2
  npm install -g lefthook
  echo "✅ lefthook installed." >&2
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
for _tool in $_tools; do
  case "$_tool" in
    pyyaml) _install_pyyaml ;;
    jsonschema) _install_jsonschema ;;
    shfmt) _install_shfmt ;;
    shellcheck) _install_shellcheck ;;
    just) _install_just ;;
    lefthook) _install_lefthook ;;
    *)
      echo "Unknown tool: $_tool" >&2
      exit 1
      ;;
  esac
done
