# shellcheck shell=bash
# Advisory file locking: serialize concurrent writers around a lockfile.
#
# Wraps `flock` to ensure only one writer holds the lockfile at a time. Use
# when multiple parallel feature installers may write to the same resource.

read -r -d '' _LOCK__FLOCK_MANIFEST << 'EOF' || true
packages:
  - when: {kernel: linux}
    packages: [util-linux]
EOF

# _lock__ensure_flock (internal) — Attempt to install util-linux so flock is available.
# Returns 0 when flock is on PATH; 1 otherwise. Non-fatal: caller falls back to spin-lock.
_lock__ensure_flock() {
  command -v flock > /dev/null 2>&1 && return 0
  # flock is a Linux kernel utility; no macOS equivalent exists — skip install attempt entirely.
  if [[ "$(os__kernel)" != "Darwin" ]]; then
    ospkg__run --manifest "$_LOCK__FLOCK_MANIFEST" --build-group "lib-lock" || true
    command -v flock > /dev/null 2>&1 && return 0
  fi
  logging__info "'flock' not available; using spin-lock fallback."
  return 1
}

# @brief lock__run_with_lockfile <lockfile> <command-string> — Run eval on command-string while holding an exclusive lock.
#
# Uses flock(1) when available; otherwise a mkdir spin-lock in the same directory with a ~30s timeout.
#
# Args:
#   <lockfile>        Path to the lockfile (created if absent).
#   <command-string>  Shell command string to eval under the lock.
lock__run_with_lockfile() {
  local _lock="${1-}" _cmd="${2-}"
  [[ -n "$_lock" ]] || {
    logging__error "lockfile path is required."
    return 1
  }
  [[ -n "$_cmd" ]] || {
    logging__error "command string is required."
    return 1
  }
  mkdir -p "$(dirname "$_lock")" 2> /dev/null || true
  if _lock__ensure_flock; then
    (
      flock 9 || {
        logging__error "could not lock ${_lock}"
        exit 1
      }
      eval "$_cmd"
    ) 9> "$_lock"
    return $?
  fi
  local _d="${_lock}.dir" _n=0
  while ! mkdir "$_d" 2> /dev/null; do
    sleep 0.05
    _n=$((_n + 1))
    if ((_n > 600)); then
      logging__error "lock wait timeout ${_d}"
      return 1
    fi
  done
  trap 'rmdir "$_d" 2>/dev/null || true' RETURN
  eval "$_cmd"
  local _ec=$?
  rmdir "$_d" 2> /dev/null || true
  trap - RETURN
  return "$_ec"
}
