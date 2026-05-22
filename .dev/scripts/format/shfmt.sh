#!/usr/bin/env bash

# Run shfmt.
#
# When no paths are provided, runs shfmt
# on tracked .sh/.bash files (except features/*/install.bash)
# plus src/*/install.bash.
# With paths, runs shfmt on those paths alone.
#
# Usage:
#   shfmt.sh [--check] [paths...]
#
# Options:
#   --check  Diff mode (no writes); exits non-zero if any file differs.

set -euo pipefail

check=false
if [[ "${1:-}" == "--check" ]]; then
  check=true
  shift
fi

if "$check"; then
  cmd=(shfmt --diff)
else
  cmd=(shfmt --write)
fi

if [[ $# -gt 0 ]]; then
  "${cmd[@]}" "$@"
else
  {
    # All tracked .sh/.bash files
    git ls-files -- '*.sh' '*.bash'
  } | sort -u | xargs "${cmd[@]}"
fi
