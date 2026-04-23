#!/bin/sh
# get.sh — Thin POSIX sh bootstrap for the sysset installer.
#
# Finds (or installs) bash >=4, detects a fetch tool, downloads get.bash from
# the repo, and hands off via exec. All arguments are forwarded verbatim.
#
# Usage:
#   sh get.sh <feature>[@<version>] [feature-opts...]
#   sh get.sh <devcontainer.json[.jsonc]>
#
# Environment overrides:
#   SYSSET_RAW_BASE   Raw GitHub base URL  (default: main branch of SYSSET_REPO)
#   SYSSET_FETCH_TOOL Override fetch tool  (curl|wget; auto-detected when unset)
set -eu

SYSSET_REPO="quantized8/sysset"
SYSSET_RAW_BASE="${SYSSET_RAW_BASE:-https://raw.githubusercontent.com/${SYSSET_REPO}/main}"

# ── Find bash >=4 ─────────────────────────────────────────────────────────────

_find_bash4() {
  for _c in bash \
    /usr/local/bin/bash \
    /opt/homebrew/bin/bash \
    /opt/local/bin/bash \
    "$HOME/.nix-profile/bin/bash" \
    /nix/var/nix/profiles/default/bin/bash; do
    command -v "$_c" > /dev/null 2>&1 || continue
    # shellcheck disable=SC2016
    _v=$("$_c" -c 'echo ${BASH_VERSINFO[0]}' 2> /dev/null) || continue
    [ "${_v:-0}" -ge 4 ] && {
      echo "$_c"
      return 0
    }
  done
  return 1
}

if ! _find_bash4 > /dev/null 2>&1; then
  echo "🔍 bash >=4 not found — installing via system package manager." >&2
  if command -v apk > /dev/null 2>&1; then
    apk add --no-cache bash
  elif command -v apt-get > /dev/null 2>&1; then
    apt-get update && apt-get install -y --no-install-recommends bash
  elif command -v dnf > /dev/null 2>&1; then
    dnf install -y bash
  elif command -v microdnf > /dev/null 2>&1; then
    microdnf install -y bash
  elif command -v yum > /dev/null 2>&1; then
    yum install -y bash
  elif command -v zypper > /dev/null 2>&1; then
    zypper --non-interactive install bash
  elif command -v pacman > /dev/null 2>&1; then
    pacman -S --noconfirm --needed bash
  elif command -v brew > /dev/null 2>&1; then
    brew install bash
  elif command -v port > /dev/null 2>&1; then
    port install bash
  elif command -v nix-env > /dev/null 2>&1; then
    nix-env -i bash
  else
    echo "⛔ No supported package manager found to install bash >=4." >&2
    exit 1
  fi
fi

_BASH4=$(_find_bash4) || {
  echo "⛔ bash >=4 still not found after installation attempt." >&2
  exit 1
}

# ── Detect fetch tool ─────────────────────────────────────────────────────────

if [ -z "${SYSSET_FETCH_TOOL:-}" ]; then
  if command -v curl > /dev/null 2>&1; then
    SYSSET_FETCH_TOOL="curl"
  elif command -v wget > /dev/null 2>&1; then
    SYSSET_FETCH_TOOL="wget"
  else
    echo "⛔ Neither curl nor wget found. Install one and retry." >&2
    exit 1
  fi
fi
export SYSSET_FETCH_TOOL

# ── Download get.bash and exec ────────────────────────────────────────────────

_tmpdir="$(mktemp -d)"
trap 'rm -rf "$_tmpdir"' EXIT

_get_bash_url="${SYSSET_RAW_BASE}/get.bash"

if [ "$SYSSET_FETCH_TOOL" = "wget" ]; then
  wget -qO "$_tmpdir/get.bash" --tries=3 --waitretry=5 "$_get_bash_url"
else
  curl -fsSL --retry 3 --retry-delay 5 "$_get_bash_url" -o "$_tmpdir/get.bash"
fi

exec "$_BASH4" "$_tmpdir/get.bash" "$@"
