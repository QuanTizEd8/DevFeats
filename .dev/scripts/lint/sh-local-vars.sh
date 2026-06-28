#!/usr/bin/env bash
# Run lib-local-vars.py on lib/*.{bash,sh} (or explicit paths).
#
# Usage:
#   sh-local-vars.sh [paths...]

set -euo pipefail

_script_dir="$(cd "$(dirname "$0")" && pwd)"
_repo_root="$(git -C "$_script_dir" rev-parse --show-toplevel 2> /dev/null || cd "$_script_dir/../../.." && pwd)"

if [[ $# -gt 0 ]]; then
  python3 "$_script_dir/lib-local-vars.py" "$@"
else
  python3 "$_script_dir/lib-local-vars.py"
fi
