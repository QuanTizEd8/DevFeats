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

# ── Pinned versions ────────────────────────────────────────────────────────────
SHFMT_VERSION="v3.13.1"
SHELLCHECK_VERSION="v0.10.0"
JUST_VERSION="1.50.0"

# ── Parse --tools flag ─────────────────────────────────────────────────────────
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/.." && pwd)"

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

_install_shfmt() {
  if _has shfmt && [[ "$(shfmt --version 2> /dev/null)" == "${SHFMT_VERSION}" ]]; then
    echo "✅ shfmt ${SHFMT_VERSION} already installed — skipping." >&2
    return
  fi
  echo "▶ Installing shfmt ${SHFMT_VERSION}..." >&2
  if [[ "$_os" == "Darwin" ]]; then
    # Homebrew doesn't pin versions easily; install via curl same as Linux
    _arch="$(uname -m)"
    [[ "$_arch" == "arm64" ]] && _arch="arm64" || _arch="amd64"
    _shfmt_bin="shfmt_${SHFMT_VERSION}_darwin_${_arch}"
  else
    _arch="$(uname -m)"
    [[ "$_arch" == "aarch64" ]] && _arch="arm64" || _arch="amd64"
    _shfmt_bin="shfmt_${SHFMT_VERSION}_linux_${_arch}"
  fi
  curl -fsSL \
    "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/${_shfmt_bin}" \
    -o /usr/local/bin/shfmt
  chmod +x /usr/local/bin/shfmt
  echo "✅ shfmt ${SHFMT_VERSION} installed." >&2
}

_install_shellcheck() {
  if _has shellcheck; then
    echo "✅ shellcheck already installed — skipping." >&2
    return
  fi
  echo "▶ Installing shellcheck ${SHELLCHECK_VERSION}..." >&2
  _arch="$(uname -m)"
  if [[ "$_os" == "Darwin" ]]; then
    [[ "$_arch" == "arm64" ]] && _sc_arch="aarch64" || _sc_arch="x86_64"
    _sc_tar="shellcheck-${SHELLCHECK_VERSION}.darwin.${_sc_arch}.tar.xz"
  else
    [[ "$_arch" == "aarch64" ]] && _sc_arch="aarch64" || _sc_arch="x86_64"
    _sc_tar="shellcheck-${SHELLCHECK_VERSION}.linux.${_sc_arch}.tar.xz"
  fi
  _tmpdir="$(mktemp -d)"
  curl -fsSL \
    "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${_sc_tar}" \
    -o "${_tmpdir}/${_sc_tar}"
  tar -xJf "${_tmpdir}/${_sc_tar}" -C "${_tmpdir}"
  install -m 0755 "${_tmpdir}/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck
  rm -rf "${_tmpdir}"
  echo "✅ shellcheck ${SHELLCHECK_VERSION} installed." >&2
}

_install_just() {
  if _has just && [[ "$(just --version 2> /dev/null)" == "just ${JUST_VERSION}" ]]; then
    echo "✅ just ${JUST_VERSION} already installed — skipping." >&2
    return
  fi
  echo "▶ Installing just ${JUST_VERSION}..." >&2
  _arch="$(uname -m)"
  if [[ "$_os" == "Darwin" ]]; then
    [[ "$_arch" == "arm64" ]] && _triple="aarch64-apple-darwin" || _triple="x86_64-apple-darwin"
  else
    [[ "$_arch" == "aarch64" ]] && _triple="aarch64-unknown-linux-musl" || _triple="x86_64-unknown-linux-musl"
  fi
  _just_tar="just-${JUST_VERSION}-${_triple}.tar.gz"
  _tmpdir="$(mktemp -d)"
  curl -fsSL \
    "https://github.com/casey/just/releases/download/${JUST_VERSION}/${_just_tar}" \
    -o "${_tmpdir}/${_just_tar}"
  tar -xzf "${_tmpdir}/${_just_tar}" -C "${_tmpdir}" just
  install -m 0755 "${_tmpdir}/just" /usr/local/bin/just
  rm -rf "${_tmpdir}"
  echo "✅ just ${JUST_VERSION} installed." >&2
}

_install_devcontainers_cli() {
  if _has devcontainer; then
    echo "✅ devcontainers-cli already installed — skipping." >&2
    return
  fi
  echo "▶ Installing @devcontainers/cli..." >&2
  npm install -g @devcontainers/cli
  echo "✅ @devcontainers/cli installed." >&2
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
    devcontainers-cli) _install_devcontainers_cli ;;
    lefthook) _install_lefthook ;;
    *)
      echo "Unknown tool: $_tool" >&2
      exit 1
      ;;
  esac
done
