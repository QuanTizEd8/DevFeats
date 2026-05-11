#!/usr/bin/env bash
# Print one field from a YAML file under .config/ using yq (Mike Farah).
#
# Preferred entry point:
#   just show-config <file> <key>
#
# Direct invocation (same arguments):
#   bash .dev/scripts/show/config.sh <file> <key>
#
#   file — basename without .yaml (e.g. ci, project)
#   key  — yq path (e.g. image.suffix)

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf '%s\n' \
    "Usage: just show-config <file> <key>" \
    "  file — .config/<file>.yaml (without extension)" \
    "  key  — yq expression path (e.g. image.suffix)" \
    "Example: just show-config ci image.suffix" >&2
  exit 0
fi

if (($# != 2)); then
  printf 'Expected exactly 2 arguments (file, key); got %d. Try: just show-config --help\n' "$#" >&2
  exit 1
fi

_file="${1:?}"
_key="${2:?}"

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${REPO_ROOT:-}" ]]; then
  _repo_root="$REPO_ROOT"
else
  _repo_root="$(git -C "$_script_dir" rev-parse --show-toplevel)"
fi

_yaml="${_repo_root}/.config/${_file}.yaml"
if [[ ! -f "$_yaml" ]]; then
  printf '⛔ No such config file: %s\n' "$_yaml" >&2
  exit 1
fi

_yq_ver="$(yq --version 2>&1 || true)"
if [[ "$_yq_ver" != *"github.com/mikefarah/yq"* ]]; then
  printf '⛔ This recipe needs mikefarah/yq (yq v4). Found: %s\n' "${_yq_ver:-unknown}" >&2
  printf '   Install: https://github.com/mikefarah/yq — or use the repo dev container (install-yq feature).\n' >&2
  exit 1
fi

yq e ".${_key}" "$_yaml"
