#!/usr/bin/env bash
set -euo pipefail

# Prefer `python` (conda-friendly); fall back to `python3` when needed.
if command -v python > /dev/null 2>&1; then
  exec python "$@"
elif command -v python3 > /dev/null 2>&1; then
  exec python3 "$@"
else
  echo "Error: neither 'python' nor 'python3' is available in PATH." >&2
  exit 127
fi
