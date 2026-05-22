# shellcheck shell=bash
# User management: resolve users, set login shells, manage installation prefixes.
#
# Provides helpers for detecting root, resolving the remote user list from
# devcontainer env vars, managing file permissions, and setting the login shell
# for one or more users. Works on Alpine (patching PAM), Debian-based, and macOS.

read -r -d '' _USERS__SHADOW_UTILS_MANIFEST << 'EOF' || true
packages:
  - when: {pm: apt}
    packages: [passwd]
  - when: {pm: [apk, zypper, pacman]}
    packages: [shadow]
  - when: {pm: [dnf, yum]}
    packages: [shadow-utils]
EOF

read -r -d '' _USERS__CHSH_MANIFEST << 'EOF' || true
packages:
  - when: {pm: apt}
    packages: [passwd]
  - when: {pm: apk}
    packages: [shadow]
  - when: {pm: [dnf, yum]}
    packages: [util-linux-user]
  - when: {pm: [zypper, pacman]}
    packages: [util-linux]
EOF

# @brief users__is_root — Return 0 when the current process runs as root (uid 0), 1 otherwise.
#
# Returns: 0 if uid is 0, 1 otherwise.
users__is_root() {
  [ "$(id -u)" -eq 0 ]
}

# @brief users__is_privileged — Return 0 when the current process can run privileged commands.
#
# A process is considered privileged when it is root (uid 0), or when `sudo`
# is installed and configured for passwordless operation.
#
# No output is produced; intended as a boolean predicate.
#
# Returns: 0 if privileged, 1 otherwise.
users__is_privileged() {
  users__is_root && return 0
  command -v sudo > /dev/null 2>&1 && sudo -n true 2> /dev/null
}

# @brief users__run_as <user> [--cwd <dir>] -- <command> [args] — Run a command as `<user>`: in-process if already that user, otherwise via `su -l` with bash-quoted argv.
#
# Requires `bash` on PATH for the non-self path.
#
# Args:
#   <user>       Username to run as.
#   --cwd <dir>  Working directory for the command (optional).
#   -- <cmd>...  Command and arguments to execute.
users__run_as() {
  if [ -z "$1" ]; then
    return 1
  fi
  _or_u=$1
  shift
  _or_cd=""
  case $1 in
    --cwd)
      _or_cd=$2
      if [ -z "$_or_cd" ]; then
        return 1
      fi
      shift 2
      ;;
  esac
  case $1 in
    --) shift ;;
  esac
  if [ $# -eq 0 ]; then
    return 1
  fi

  if [ "$(users__get_current --no-sudo)" = "$_or_u" ]; then
    if [ -n "$_or_cd" ]; then
      (cd "$_or_cd" && "$@")
    else
      "$@"
    fi
    return $?
  fi
  if ! command -v bash > /dev/null 2>&1; then
    logging__error "users__run_as: bash is required to run a command as another user"
    return 1
  fi
  # shellcheck disable=SC2016  # $a is intentionally single-quoted — it is bash's variable, not the current shell's
  _or_c="$(bash -c 'for a; do printf " %q" "$a"; done; echo' sh "$@")"
  _or_c="${_or_c# }" # strip the single leading space; $(...) already strips the trailing newline
  if [ -n "$_or_cd" ]; then
    _or_cd_q="$(bash -c 'printf "%q" "$1"' bash "$_or_cd")"
    users__run_privileged su -l "$_or_u" -c "cd ${_or_cd_q} && ${_or_c}"
  else
    users__run_privileged su -l "$_or_u" -c "$_or_c"
  fi
  return $?
}

# @brief users__run_privileged <cmd> [<args>...] — Run a command as root.
#
# If already root (uid 0), runs directly. Otherwise requires sudo to be
# pre-installed and configured for passwordless operation.
#
# Args:
#   <cmd> [<args>...]  Command and arguments to execute.
#
# Returns: the exit code of <cmd>.
users__run_privileged() {
  if users__is_root; then
    "$@"
  else
    if ! command -v sudo > /dev/null 2>&1; then
      logging__error "users__run_privileged: sudo is not installed (cmd='${*}')"
      return 1
    fi
    if ! sudo -n true 2> /dev/null; then
      logging__error "users__run_privileged: passwordless sudo required but not available (uid=$(id -u), user=$(id -un), cmd='${*}')"
      return 1
    fi
    sudo -n "$@"
  fi
}

# @brief users__default_prefix — Print the default binary installation prefix: `/usr/local` as root, `$HOME/.local` as non-root.
#
# Stdout: `/usr/local` when root, `$HOME/.local` otherwise.
users__default_prefix() {
  if users__is_root; then
    printf '%s\n' "/usr/local"
  else
    printf '%s\n' "${HOME}/.local"
  fi
}

# @brief users__uid_of_path_owner <path> — Print the numeric owner UID of the given path.
#
# Portable: tries `stat -f '%u'` (macOS) first, then `stat -c '%u'` (Linux).
#
# Args:
#   <path>  Absolute path to query (must exist).
#
# Stdout: owner UID as a decimal string.
users__uid_of_path_owner() {
  stat -c '%u' "$1" 2> /dev/null || stat -f '%u' "$1" 2> /dev/null
}

# @brief users__home_of_path_owner <path> — Print the home directory of the user who owns the nearest existing ancestor of <path>.
#
# When root is installing into a regular user's prefix (e.g. `/home/vscode/.local`),
# shell config files must be written to the *owning* user's home (`/home/vscode`),
# not to root's home. This function resolves that home via `getent passwd <uid>`
# (falling back to `/etc/passwd` on systems without `getent`, e.g. macOS).
#
# Falls back to `${HOME:-/root}` when the path is already under `$HOME`, the
# owner UID is a system account (< 1000 or ≥ 65534), the UID has no passwd
# entry, or the calling process is not root.
#
# Args:
#   <path>  Absolute path whose owning user's home to resolve (need not exist).
#
# Stdout: absolute path to the relevant home directory.
users__home_of_path_owner() {
  local _p="$1"
  # Fast path: already under the current user's home.
  [[ -n "${HOME:-}" && "$_p" == "${HOME}/"* ]] && {
    printf '%s\n' "$HOME"
    return 0
  }
  if users__is_root; then
    local _existing _uid _home
    _existing="$(file__nearest_existing "$_p")"
    _uid="$(users__uid_of_path_owner "$_existing")"
    if [[ "$_uid" =~ ^[0-9]+$ ]] && ((_uid >= 1000 && _uid < 65534)); then
      _home="$(getent passwd "$_uid" 2> /dev/null | cut -d: -f6)"
      [[ -z "$_home" ]] && _home="$(awk -F: -v u="$_uid" '$3==u{print $6;exit}' /etc/passwd 2> /dev/null)"
      [[ -n "$_home" ]] && {
        printf '%s\n' "$_home"
        return 0
      }
    fi
  fi
  printf '%s\n' "${HOME:-/root}"
}

# @brief users__resolve_list — Print one deduplicated username per line.
#
# Root is excluded from auto-detected paths (_REMOTE_USER, _CONTAINER_USER,
# SUDO_USER) when other non-root users are found; it is only added as a
# fallback when no other user is resolved (e.g. plain container image or
# standalone macOS install). Root is always accepted via --user.
#
# Args:
#   [--current <bool>]    Include SUDO_USER / current user (default: true).
#   [--remote <bool>]     Include _REMOTE_USER (default: true).
#   [--container <bool>]  Include _CONTAINER_USER (default: true).
#   [--user <name>]...    Extra explicit usernames; root allowed; repeatable.
#
# Stdout: one username per line.
users__resolve_list() {
  local _include_current="true"
  local _include_remote="true"
  local _include_container="true"
  local -a _extra_users=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --current)
        _include_current="$2"
        shift 2
        ;;
      --remote)
        _include_remote="$2"
        shift 2
        ;;
      --container)
        _include_container="$2"
        shift 2
        ;;
      --user)
        _extra_users+=("$2")
        shift 2
        ;;
      *) shift ;;
    esac
  done

  local _seen="" _out="" _root_queued=false

  _users_add() {
    local _name="$1"
    [ -z "$_name" ] && return 0
    case " ${_seen} " in
      *" ${_name} "*) return 0 ;;
    esac
    _seen="${_seen} ${_name}"
    _out="${_out} ${_name}"
    return 0
  }

  if [ "${_include_current}" = "true" ]; then
    local _cur
    _cur="$(users__get_current)"
    if [ "$_cur" != "root" ]; then
      _users_add "$_cur"
    else
      _root_queued=true
    fi
  fi

  if [ "${_include_remote}" = "true" ] && [ -n "${_REMOTE_USER:-}" ]; then
    [ "${_REMOTE_USER}" != "root" ] && _users_add "${_REMOTE_USER}"
  fi

  if [ "${_include_container}" = "true" ] && [ -n "${_CONTAINER_USER:-}" ]; then
    [ "${_CONTAINER_USER}" != "root" ] && _users_add "${_CONTAINER_USER}"
  fi

  local _extra
  for _extra in "${_extra_users[@]+"${_extra_users[@]}"}"; do
    [ -n "$_extra" ] && _users_add "$_extra"
  done

  if [ "$_root_queued" = "true" ] && [ -z "$_out" ]; then
    _users_add "root"
  fi

  if [ -n "$_out" ]; then
    logging__info "users__resolve_list: resolved users='${_out# }'"
  else
    logging__info "users__resolve_list: resolved users='(empty)'"
  fi

  local _name
  for _name in $_out; do
    printf '%s\n' "$_name"
  done
  return 0
}

# @brief users__set_write_permissions <prefix> <owner> <group> [<user>...] — Create OS group, add listed users, then apply group-write bits on a shared installation prefix.
#
# Sets the setgid bit on all subdirectories so new files inherit the group.
# Uses dseditgroup on macOS and groupadd/usermod on Linux.
#
# Args:
#   <prefix>     Absolute path to the installation directory.
#   <owner>      Username of the primary file owner (chown target).
#   <group>      OS group name to create (if absent) and use.
#   [<user>...]  Additional users to add to the group.
users__set_write_permissions() {
  local _path="$1" _owner="$2" _group="$3"
  shift 3
  logging__info "Setting write permissions on '${_path}' (owner: '${_owner}', group: '${_group}')."
  if command -v dseditgroup > /dev/null 2>&1; then
    dseditgroup -o read "$_group" > /dev/null 2>&1 || users__run_privileged dseditgroup -o create -q "$_group"
    local _u
    for _u in "$@"; do
      [ -z "$_u" ] && continue
      dseditgroup -o checkmember -m "$_u" "$_group" > /dev/null 2>&1 ||
        users__run_privileged dseditgroup -o edit -a "$_u" -t user "$_group"
    done
  else
    if ospkg__run --manifest "$_USERS__SHADOW_UTILS_MANIFEST" --build-group "lib-users" --skip_installed; then
      getent group "$_group" > /dev/null 2>&1 || users__run_privileged groupadd -r "$_group"
      local _u
      for _u in "$@"; do
        [ -z "$_u" ] && continue
        id -nG "$_u" 2> /dev/null | grep -qw "$_group" && continue
        if command -v usermod > /dev/null 2>&1; then
          users__run_privileged usermod -a -G "$_group" "$_u"
        else
          logging__warn "usermod not found — cannot add '${_u}' to group '${_group}'."
        fi
      done
    else
      logging__warn "Neither dseditgroup nor groupadd found — skipping group setup."
    fi
  fi
  users__run_privileged chown -R "${_owner}:${_group}" "$_path"
  users__run_privileged chmod -R g+rwX "$_path"
  while IFS= read -r -d '' _dir; do
    users__run_privileged chmod g+s "$_dir"
  done < <(find "$_path" -type d -print0)
  return 0
}

# @brief users__ensure_setuid <binary>... — Locate each binary with `command -v` and set the setuid bit.
#
# Uses `command -v` for portable binary discovery across distros where binaries
# may live in `/usr/bin`, `/usr/sbin`, or `/sbin` (e.g. `newuidmap`/`newgidmap`
# on Fedora/RHEL/Alpine). Logs a warning when a binary is not found or `chmod`
# fails, but does not abort.
#
# Args:
#   <binary>...  One or more binary names (not full paths) to locate and set setuid on.
#
# Returns: 0 always (best-effort; individual failures are logged as warnings).
users__ensure_setuid() {
  local _bin _path
  for _bin in "$@"; do
    _path="$(command -v "$_bin" 2> /dev/null)" || true
    if [ -z "$_path" ]; then
      logging__warn "users__ensure_setuid: '${_bin}' not found on PATH — skipping setuid"
      continue
    fi
    if users__run_privileged chmod u+s "$_path"; then
      logging__info "users__ensure_setuid: set setuid on '${_path}'"
    else
      logging__warn "users__ensure_setuid: chmod u+s '${_path}' failed"
    fi
  done
  return 0
}

# @brief users__next_subid_offset <file> — Print the next available subuid/subgid offset beyond all existing ranges in <file>.
#
# Scans every entry in <file> (format: `user:start:count`) and returns
# `max(start + count)` across all entries, floored at 100000 (the
# conventional minimum subordinate-ID starting point). This ensures a new
# range appended immediately after the returned offset will never overlap
# any pre-existing range — including ranges written by the base image or
# other features.
#
# Args:
#   <file>  Path to `/etc/subuid` or `/etc/subgid`.
#
# Stdout: next available offset (integer ≥ 100000).
users__next_subid_offset() {
  local _file="$1"
  local _max=100000
  local _user _start _count _end
  [ -f "$_file" ] || {
    printf '%s\n' "$_max"
    return 0
  }
  while IFS=: read -r _user _start _count; do
    # Skip comment lines and blank/malformed entries.
    case "$_user" in '#'* | '') continue ;; esac
    case "$_start" in '' | *[!0-9]*) continue ;; esac
    case "$_count" in '' | *[!0-9]*) continue ;; esac
    _end=$((_start + _count))
    [ "$_end" -gt "$_max" ] && _max="$_end"
  done < "$_file"
  printf '%s\n' "$_max"
  return 0
}

# @brief users__set_login_shell <shell_path> <username>... — Register `<shell_path>` in `/etc/shells`, patch Alpine PAM if needed, then call `chsh -s` for each user.
#
# Exits early with a warning (not an error) if chsh is not installed.
# Skips users whose login shell is already set to <shell_path>. Logs a
# warning when chsh fails for a user but does not abort.
#
# On Alpine: patches /etc/pam.d/chsh to allow root to run chsh without a
# password (inserts "auth sufficient pam_rootok.so" if not already present).
#
# Args:
#   <shell_path>   Absolute path to the shell binary (e.g. `/bin/zsh`).
#   <username>...  One or more usernames to update.
#
# Returns: 0 on success (warnings logged for individual failures, not propagated).
users__set_login_shell() {
  local _shell="$1"
  shift

  if ! ospkg__run --manifest "$_USERS__CHSH_MANIFEST" --build-group "lib-users" --skip_installed; then
    logging__warn "chsh not found — skipping shell change."
    return 0
  fi

  # Register the shell in /etc/shells.
  local _shells_file=/etc/shells
  [ -f /usr/share/defaults/etc/shells ] && _shells_file=/usr/share/defaults/etc/shells
  if [ -f "$_shells_file" ] && ! grep -qx "$_shell" "$_shells_file" 2> /dev/null; then
    printf '%s\n' "$_shell" | file__append_privileged "$_shells_file"
    logging__info "Added '${_shell}' to '${_shells_file}'."
  fi

  # Alpine PAM: chsh requires a password even when run as root unless
  # pam_rootok.so is listed as sufficient.
  if [ -f /etc/pam.d/chsh ]; then
    if ! grep -Eq '^auth[[:blank:]]+sufficient[[:blank:]]+pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
      if grep -Eq '^auth(.*)pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
        awk '/^auth(.*)pam_rootok\.so$/ { $2 = "sufficient" } { print }' \
          /etc/pam.d/chsh > /tmp/_chsh.tmp && users__run_privileged mv /tmp/_chsh.tmp /etc/pam.d/chsh
      else
        printf 'auth sufficient pam_rootok.so\n' | file__append_privileged /etc/pam.d/chsh
      fi
      logging__info "Fixed pam_rootok.so in /etc/pam.d/chsh."
    fi
  fi

  for _username in "$@"; do
    [ -z "$_username" ] && continue
    _current_shell="$(getent passwd "$_username" 2> /dev/null | cut -d: -f7 || true)"
    if [ "$_current_shell" = "$_shell" ]; then
      logging__info "Shell for '${_username}' already set to '${_shell}'."
      continue
    fi
    if users__run_privileged chsh -s "$_shell" "$_username"; then
      logging__success "Shell for '${_username}' set to '${_shell}'."
    else
      logging__warn "chsh failed for '${_username}'."
    fi
  done
  return 0
}

# @brief users__create_system_user <username> [--home <path>] [--shell <shell>] — Create a system user if it does not already exist.
#
# Ensures useradd is available, installing the appropriate shadow package if needed.
# No-op if the user already exists.
#
# Args:
#   <username>       Login name for the new user.
#   --home <path>    Home directory. Optional.
#   --shell <shell>  Login shell. Optional.
#
# Returns: 0 on success or if user already exists, 1 if useradd cannot be installed.
users__create_system_user() {
  local _username="$1"
  shift
  local _home="" _shell=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --home)
        _home="$2"
        shift 2
        ;;
      --shell)
        _shell="$2"
        shift 2
        ;;
      *) shift ;;
    esac
  done
  if id "$_username" > /dev/null 2>&1; then
    logging__info "User '${_username}' already exists — skipping."
    return 0
  fi
  if ! ospkg__run --manifest "$_USERS__SHADOW_UTILS_MANIFEST" --build-group "lib-users" --skip_installed; then
    logging__warn "useradd not found — cannot create user '${_username}'."
    return 1
  fi
  local -a _cmd=("useradd" "--system" "--create-home")
  [ -n "$_home" ] && _cmd+=("--home-dir" "$_home")
  [ -n "$_shell" ] && _cmd+=("--shell" "$_shell")
  _cmd+=("$_username")
  users__run_privileged "${_cmd[@]}"
  logging__success "Created system user '${_username}'."
  return 0
}

# @brief users__get_current [--no-sudo] — Print the current username using a robust fallback chain.
#
# Resolution order (default):
# SUDO_USER (when running via sudo) → whoami → id -un → /etc/passwd scan → USER → LOGNAME.
#
# Args:
#   [--no-sudo]  Skip SUDO_USER and always return the effective user (the process owner).
#
# Stdout: username string.
#
# Returns: 0 on success, 1 if no username can be determined.
users__get_current() {
  if [ "${1:-}" != "--no-sudo" ] && [ -n "${SUDO_USER:-}" ]; then
    printf '%s\n' "${SUDO_USER}"
    return 0
  fi

  if command -v whoami > /dev/null 2>&1; then
    printf '%s\n' "$(whoami 2> /dev/null || true)"
    return 0
  fi

  if command -v id > /dev/null 2>&1; then
    _uc_cur="$(id -un 2> /dev/null || true)"
    if [ -z "${_uc_cur}" ] && [ -r /etc/passwd ]; then
      _uc_uid="$(id -u 2> /dev/null || true)"
      [ -n "${_uc_uid}" ] && _uc_cur="$(awk -F: -v uid="${_uc_uid}" '$3==uid {print $1; exit}' /etc/passwd 2> /dev/null || true)"
    fi
    if [ -n "${_uc_cur}" ]; then
      printf '%s\n' "${_uc_cur}"
      return 0
    fi
  fi

  if [ -n "${USER:-}" ]; then
    printf '%s\n' "${USER}"
    return 0
  fi

  if [ -n "${LOGNAME:-}" ]; then
    printf '%s\n' "${LOGNAME}"
    return 0
  fi

  logging__error "users__get_current: unable to determine current user"
  return 1
}

# @brief users__resolve_home <username> — Print the home directory for the given user.
#
# Resolution order:
#   1. `getent passwd` when available (Linux, most distros including Debian,
#      Alpine with shadow package, RHEL, and SUSE). This is the most reliable
#      source as it queries NSS and handles LDAP / NIS users too.
#   2. Direct scan of `/etc/passwd` — fallback for images without `getent`
#      (e.g. minimal Alpine before the shadow package is installed, macOS
#      where `getent` is absent).
#   3. Tilde expansion via `eval echo "~<username>"` as a last resort. This
#      works in most shells but may produce the literal `~user` string on
#      systems where the user does not have a home entry recognised by the
#      shell; callers should validate the result when exactness matters.
#
# Args:
#   <username>  Username to look up.
#
# Stdout: absolute path to the home directory.
# Returns: 0 always (tilde expansion is the final fallback and never fails).
users__resolve_home() {
  local _user="$1" _entry
  if command -v getent > /dev/null 2>&1; then
    _entry="$(getent passwd "$_user" 2> /dev/null)"
  else
    _entry="$(grep -m1 "^${_user}:" /etc/passwd 2> /dev/null)"
  fi
  if [ -n "$_entry" ]; then
    local _home
    IFS=: read -r _ _ _ _ _ _home _ <<< "$_entry"
    printf '%s\n' "$_home"
    return 0
  fi
  eval echo "~${_user}"
}
