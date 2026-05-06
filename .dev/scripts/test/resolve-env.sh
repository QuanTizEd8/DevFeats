#!/usr/bin/env bash
# Usage: resolve-env.sh <env-name> [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]
# Prints the Docker image name to use (possibly after building it).
# For macOS environments, prints the runner label directly (no Docker build).
set -euo pipefail

_ENV_NAME="${1:?usage: resolve-env.sh <env-name> [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]}"
shift
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$_SCRIPT_DIR" rev-parse --show-toplevel)}"
export REPO_ROOT
exec proman-test-resolve-env "$_ENV_NAME" "$@"
