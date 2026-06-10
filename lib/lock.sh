# shellcheck shell=bash
# Advisory file locking: serialize concurrent writers around a lockfile.
#
# Wraps `flock` to ensure only one writer holds the lockfile at a time. Use
# when multiple parallel feature installers may write to the same resource.

lock__run_with_lockfile() {
  # @brief lock__run_with_lockfile <lockfile> <command-string> — Run eval on command-string while holding an exclusive lock.
  #
  # Uses flock(1) when available; otherwise a mkdir spin-lock in the same directory with a ~30s timeout.
  #
  # Args:
  #   <lockfile>        Path to the lockfile (created if absent).
  #   <command-string>  Shell command string to eval under the lock.
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
  if bootstrap__flock; then
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
