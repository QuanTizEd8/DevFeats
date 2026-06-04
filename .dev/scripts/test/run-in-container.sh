#!/usr/bin/env bash
# Usage: run-in-container.sh --image <image> --run <cmd>
#                            [--name <label>]
#                            [--log-bind-dir <host-dir>]
#                            [--network-none]
#                            [--env KEY=VAL] ...
#
# Mounts the repo read-only at /repo, sets REPO_ROOT=/repo, passes GITHUB_TOKEN.
# With --log-bind-dir, mounts a host directory at /log-out (rw) for post-run log copy.
set -euo pipefail

_IMAGE="" _RUN_CMD="" _NAME="" _LOG_BIND_DIR="" _NET_ARGS=() _EXTRA_ENV=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      _IMAGE="$2"
      shift 2
      ;;
    --run)
      _RUN_CMD="$2"
      shift 2
      ;;
    --name)
      _NAME="$2"
      shift 2
      ;;
    --log-bind-dir)
      _LOG_BIND_DIR="$2"
      shift 2
      ;;
    --network-none)
      _NET_ARGS=("--network" "none")
      shift
      ;;
    --env)
      _EXTRA_ENV+=("-e" "$2")
      shift 2
      ;;
    *)
      printf 'Unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$_IMAGE" || -z "$_RUN_CMD" ]] && {
  echo "⛔ --image and --run required" >&2
  exit 1
}

_HOST_REPO="${HOST_REPO_ROOT:-${REPO_ROOT:-$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" rev-parse --show-toplevel)}}"
_NAME_ARGS=()
[[ -n "$_NAME" ]] && _NAME_ARGS=("--name" "$_NAME")

_LOG_VOL_ARGS=()
if [[ -n "$_LOG_BIND_DIR" ]]; then
  mkdir -p "$_LOG_BIND_DIR"
  _LOG_VOL_ARGS=(-v "${_LOG_BIND_DIR}:/log-out:rw")
fi

docker run --rm \
  "${_NAME_ARGS[@]+"${_NAME_ARGS[@]}"}" \
  "${_NET_ARGS[@]+"${_NET_ARGS[@]}"}" \
  "${_LOG_VOL_ARGS[@]+"${_LOG_VOL_ARGS[@]}"}" \
  "${_EXTRA_ENV[@]+"${_EXTRA_ENV[@]}"}" \
  -v "${_HOST_REPO}:/repo:ro" \
  -w /repo \
  -e REPO_ROOT=/repo \
  -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
  "$_IMAGE" \
  sh -c "$_RUN_CMD"
