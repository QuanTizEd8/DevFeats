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

read -r -d '' _USERS__COREUTILS_MANIFEST << 'EOF' || true
packages:
  - when: {kernel: linux}
    packages: [coreutils]
EOF

read -r -d '' _USERS__GETENT_MANIFEST << 'EOF' || true
packages:
  - when: {pm: apt}
    packages: [libc-bin]
  - when: {pm: apk}
    packages: [musl-utils]
  - when: {pm: [dnf, yum]}
    packages: [glibc-common]
  - when: {pm: [zypper, pacman]}
    packages: [glibc]
EOF

read -r -d '' _USERS__SUDO_MANIFEST << 'EOF' || true
packages:
  - sudo
EOF

# _users__ensure_coreutils (internal) — Ensure id, stat, and whoami are available; install coreutils via ospkg if absent.
_users__ensure_coreutils() {
  command -v id > /dev/null 2>&1 && return 0
  ospkg__run --manifest "$_USERS__COREUTILS_MANIFEST" --build-group "lib-users" || true
  command -v id > /dev/null 2>&1 && return 0
  logging__error "users.sh: 'id' is required but could not be installed."
  return 1
}

# _users__ensure_getent (internal) — Ensure getent is available; install the platform libc package via ospkg if absent.
# Returns 0 when getent is on PATH; 1 otherwise. Non-fatal: macOS does not have getent; callers fall back to dscl.
_users__ensure_getent() {
  command -v getent > /dev/null 2>&1 && return 0
  # getent is a Linux glibc utility; no macOS equivalent exists — skip install attempt entirely.
  if [[ "$(os__kernel)" != "Darwin" ]]; then
    ospkg__run --manifest "$_USERS__GETENT_MANIFEST" --build-group "lib-users" || true
    command -v getent > /dev/null 2>&1 && return 0
  fi
  logging__info "users.sh: 'getent' not available; falling back to dscl or /etc/passwd for home resolution."
  return 1
}

# _users__ensure_sudo (internal) — Ensure sudo (visudo) is available; install via ospkg if absent.
_users__ensure_sudo() {
  command -v visudo > /dev/null 2>&1 && return 0
  ospkg__run --manifest "$_USERS__SUDO_MANIFEST" --build-group "lib-users" || true
  command -v visudo > /dev/null 2>&1 && return 0
  logging__error "users.sh: 'sudo' (visudo) is required but could not be installed."
  return 1
}

# _users__ensure_shadowutils (internal) — Ensure useradd, groupadd, and usermod are available; install shadow-utils via ospkg if absent.
_users__ensure_shadowutils() {
  command -v groupadd > /dev/null 2>&1 && return 0
  ospkg__run --manifest "$_USERS__SHADOW_UTILS_MANIFEST" --build-group "lib-users" || true
  command -v groupadd > /dev/null 2>&1 && return 0
  logging__warn "users.sh: shadow-utils (useradd, groupadd, usermod) is required but could not be installed."
  return 1
}

# @brief users__is_root — Return 0 when the current process runs as root (uid 0), 1 otherwise.
#
# Checks via `id -u` when available; falls back to bash's $EUID when id is
# not yet installed (e.g. during the coreutils bootstrap). Returns 1 when
# neither source is available.
#
# Returns: 0 if uid is 0, 1 otherwise.
users__is_root() {
  if command -v id > /dev/null 2>&1; then
    [ "$(id -u)" -eq 0 ]
  elif [[ -n "${EUID+x}" ]]; then
    [[ ${EUID} -eq 0 ]]
  else
    return 1
  fi
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

# @brief users__can_write <path> — Return 0 if the calling process can write to <path> (or create it if nonexistent).
#
# A path is considered writable when:
#   1. The path itself (or its nearest existing ancestor) is writable by the current process, OR
#   2. Passwordless sudo is available (users__is_privileged returns 0).
#
# Args:
#   <path>  Absolute path to check (need not exist).
#
# Returns: 0 if writable or privileged, 1 otherwise.
users__can_write() {
  local _path="$1" _existing
  _existing="$(file__nearest_existing "$_path")"
  [ -w "$_existing" ] && return 0
  users__is_privileged
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
      logging__error "users__run_privileged: passwordless sudo required but not available (uid=${EUID}, user=$(id -un 2> /dev/null || printf '%s' "${USER:-?}"), cmd='${*}')"
      return 1
    fi
    sudo -n "$@"
  fi
}

# @brief users__default_prefix — Print the default binary installation prefix.
#
# Returns `/usr/local` when the calling process can write there (directly or
# via passwordless sudo). Otherwise resolves the current user's home via
# `users__resolve_home` and returns `<home>/.local`.
#
# Stdout: absolute prefix path.
users__default_prefix() {
  if users__can_write "/usr/local"; then
    printf '%s\n' "/usr/local"
    return 0
  fi
  local _home
  _home="$(users__resolve_home)"
  if [[ -z "$_home" ]]; then
    logging__error "users__default_prefix: cannot resolve home directory for current user."
    return 1
  fi
  printf '%s\n' "${_home}/.local"
}

# @brief users__primary_group_of <username> — Print the primary group name of the given user.
#
# Args:
#   <username>  Username to query.
#
# Stdout: group name string.
users__primary_group_of() {
  _users__ensure_coreutils || return 1
  id -gn "$1"
}

# @brief users__gid_of_group <groupname> — Print the numeric GID for the given group name.
#
# Args:
#   <groupname>  Group name to query.
#
# Stdout: GID as a decimal string.
# Returns: 0 on success, 1 when the group is not found.
users__gid_of_group() {
  local _gid
  if _users__ensure_getent; then
    _gid="$(getent group "$1" 2> /dev/null | cut -d: -f3)"
    [[ -n "$_gid" ]] && { printf '%s\n' "$_gid"; return 0; }
  fi
  _gid="$(awk -F: -v g="$1" '$1==g{print $3;exit}' /etc/group 2> /dev/null)"
  [[ -n "$_gid" ]] && { printf '%s\n' "$_gid"; return 0; }
  return 1
}

# @brief users__group_of_gid <gid> — Print the group name for the given numeric GID.
#
# Args:
#   <gid>  Numeric GID to query.
#
# Stdout: group name string.
# Returns: 0 on success, 1 when no group with that GID is found.
users__group_of_gid() {
  local _gname
  if _users__ensure_getent; then
    _gname="$(getent group "$1" 2> /dev/null | cut -d: -f1)"
    [[ -n "$_gname" ]] && { printf '%s\n' "$_gname"; return 0; }
  fi
  _gname="$(awk -F: -v gid="$1" '$3==gid{print $1;exit}' /etc/group 2> /dev/null)"
  [[ -n "$_gname" ]] && { printf '%s\n' "$_gname"; return 0; }
  return 1
}

# @brief users__uid_of_user <username> — Print the numeric UID of the given user.
#
# Args:
#   <username>  Username to query.
#
# Stdout: UID as a decimal string.
users__uid_of_user() {
  _users__ensure_coreutils || return 1
  id -u "$1"
}

# @brief users__username_of_uid <uid> — Print the username for the given numeric UID.
#
# Args:
#   <uid>  Numeric UID to query.
#
# Stdout: username string.
users__username_of_uid() {
  _users__ensure_coreutils || return 1
  local _uname
  _uname="$(id -un "$1" 2> /dev/null)" && {
    printf '%s\n' "$_uname"
    return 0
  }
  # busybox id(1) does not accept numeric UID arguments; fall back to passwd db.
  _uname="$(getent passwd "$1" 2> /dev/null | cut -d: -f1)"
  [[ -z "$_uname" ]] && _uname="$(awk -F: -v u="$1" '$3==u{print $1;exit}' /etc/passwd 2> /dev/null)"
  [[ -n "$_uname" ]] && {
    printf '%s\n' "$_uname"
    return 0
  }
  return 1
}

# @brief users__users_by_primary_gid <gid> — Print all usernames whose primary GID matches <gid>, one per line.
#
# Args:
#   <gid>  Numeric GID to query.
#
# Stdout: one username per line; empty when no matches are found.
users__users_by_primary_gid() {
  awk -F: -v gid="$1" '$4==gid{print $1}' /etc/passwd
}

# @brief users__group_exists <name-or-gid> — Return 0 if a group with the given name or numeric GID exists.
#
# Args:
#   <name-or-gid>  Group name or numeric GID to check.
#
# Returns: 0 if found, 1 otherwise.
users__group_exists() {
  if _users__ensure_getent; then
    getent group "$1" > /dev/null 2>&1
    return
  fi
  awk -F: -v g="$1" '$1==g || $3==g {found=1; exit} END{exit (found ? 0 : 1)}' /etc/group 2> /dev/null
}

# @brief users__uid_of_path_owner <path> — Print the numeric owner UID of the given path.
#
# Branches on os__kernel: stat -f '%u' on Darwin, stat -c '%u' on Linux.
#
# Args:
#   <path>  Absolute path to query (must exist).
#
# Stdout: owner UID as a decimal string.
users__uid_of_path_owner() {
  _users__ensure_coreutils || return 1
  if [[ "$(os__kernel)" == "Darwin" ]]; then
    stat -f '%u' "$1"
  else
    stat -c '%u' "$1"
  fi
}

# @brief users__home_of_path_owner <path> — Print the home directory of the user who owns the nearest existing ancestor of <path>.
#
# Args:
#   <path>  Absolute path (need not exist).
#
# Stdout: absolute home directory path; empty when the owner has no resolvable home.
users__home_of_path_owner() {
  local _p="$1"
  local _existing _uid
  _existing="$(file__nearest_existing "$_p")"
  _uid="$(users__uid_of_path_owner "$_existing")"
  users__resolve_home --uid "$_uid"
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

  __users__add() {
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
      __users__add "$_cur"
    else
      _root_queued=true
    fi
  fi

  if [ "${_include_remote}" = "true" ] && [ -n "${_REMOTE_USER:-}" ]; then
    [ "${_REMOTE_USER}" != "root" ] && __users__add "${_REMOTE_USER}"
  fi

  if [ "${_include_container}" = "true" ] && [ -n "${_CONTAINER_USER:-}" ]; then
    [ "${_CONTAINER_USER}" != "root" ] && __users__add "${_CONTAINER_USER}"
  fi

  local _extra
  for _extra in "${_extra_users[@]+"${_extra_users[@]}"}"; do
    [ -n "$_extra" ] && __users__add "$_extra"
  done

  if [ "$_root_queued" = "true" ] && [ -z "$_out" ]; then
    __users__add "root"
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
  _users__ensure_coreutils || return 1
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
    if ospkg__run --manifest "$_USERS__SHADOW_UTILS_MANIFEST" --build-group "lib-users"; then
      getent group "$_group" > /dev/null 2>&1 || users__run_privileged groupadd -r "$_group"
      local _u
      for _u in "$@"; do
        [ -z "$_u" ] && continue
        id -nG "$_u" 2> /dev/null | grep -qw "$_group" && continue
        users__add_to_group "$_u" "$_group"
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

  if ! ospkg__run --manifest "$_USERS__CHSH_MANIFEST" --build-group "lib-users"; then
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

# @brief users__create_group <name> [--gid <gid>] — Create a group, optionally with a specific GID.
#
# Args:
#   <name>     Group name.
#   --gid <n>  Numeric GID to assign (optional).
#
# Returns: 0 on success, 1 if groupadd cannot be installed.
users__create_group() {
  local _name="$1"
  shift
  local _gid=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gid) _gid="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  _users__ensure_shadowutils || return 1
  local -a _cmd=("groupadd")
  [ -n "$_gid" ] && _cmd+=("--gid" "$_gid")
  _cmd+=("$_name")
  users__run_privileged "${_cmd[@]}"
}

# @brief users__delete_group <name> — Delete a group by name.
#
# Args:
#   <name>  Group name to delete.
#
# Returns: 0 on success, 1 on failure (warning logged).
users__delete_group() {
  _users__ensure_shadowutils || return 1
  users__run_privileged groupdel "$1" 2> /dev/null || { logging__error "Failed to delete group '${1}'."; return 1; }
}

# @brief users__delete_user <name> — Delete a user account.
#
# Args:
#   <name>  Username to delete.
#
# Returns: 0 on success, 1 on failure (warning logged).
users__delete_user() {
  _users__ensure_shadowutils || return 1
  users__run_privileged userdel "$1" 2> /dev/null || { logging__error "Failed to delete user '${1}'."; return 1; }
}

# @brief users__create_user <name> [--uid <uid>] [--gid <gid>] [--home <path>] [--shell <shell>] [--no-create-home] — Create a regular user account.
#
# Unlike users__create_system_user, this creates a non-system user and does not
# skip existing users — conflict resolution is left to the caller.
#
# Args:
#   <name>            Login name.
#   --uid <n>         Numeric UID (optional).
#   --gid <n>         Numeric primary GID (optional).
#   --home <path>     Home directory path (optional).
#   --shell <shell>   Login shell (optional).
#   --no-create-home  Do not create the home directory.
#
# Returns: 0 on success, 1 if useradd cannot be installed.
users__create_user() {
  local _name="$1"
  shift
  local _uid="" _gid="" _home="" _shell="" _no_create_home=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --uid)            _uid="$2";   shift 2 ;;
      --gid)            _gid="$2";   shift 2 ;;
      --home)           _home="$2";  shift 2 ;;
      --shell)          _shell="$2"; shift 2 ;;
      --no-create-home) _no_create_home=true; shift ;;
      *) shift ;;
    esac
  done
  _users__ensure_shadowutils || return 1
  local -a _cmd=("useradd")
  [[ "$_no_create_home" == "true" ]] && _cmd+=("--no-create-home")
  [ -n "$_home" ]  && _cmd+=("--home-dir" "$_home")
  [ -n "$_gid" ]   && _cmd+=("--gid" "$_gid")
  [ -n "$_shell" ] && _cmd+=("--shell" "$_shell")
  [ -n "$_uid" ]   && _cmd+=("--uid" "$_uid")
  _cmd+=("$_name")
  users__run_privileged "${_cmd[@]}"
}

# @brief users__add_to_group <user> <group> — Add <user> to supplementary group <group>.
#
# Args:
#   <user>   Username to modify.
#   <group>  Group name to add the user to.
#
# Returns: 0 on success, 1 if usermod cannot be installed.
users__add_to_group() {
  local _user="$1" _group="$2"
  _users__ensure_shadowutils || return 1
  users__run_privileged usermod -aG "$_group" "$_user" || { logging__warn "Failed to add '${_user}' to group '${_group}'."; return 1; }
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
  _users__ensure_coreutils || return 1
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
  _users__ensure_shadowutils || return 1
  local -a _cmd=("useradd" "--system" "--create-home")
  [ -n "$_home" ] && _cmd+=("--home-dir" "$_home")
  [ -n "$_shell" ] && _cmd+=("--shell" "$_shell")
  _cmd+=("$_username")
  users__run_privileged "${_cmd[@]}"
  logging__success "Created system user '${_username}'."
  return 0
}

# @brief users__get_current [--no-sudo] — Print the current username.
#
# Resolution order (default): SUDO_USER → devcontainer _REMOTE_USER (non-root) /
# _CONTAINER_USER → id -un. coreutils is bootstrapped via ospkg when id is absent.
#
# Args:
#   [--no-sudo]  Skip SUDO_USER / devcontainer vars and return the effective process owner.
#
# Stdout: username string.
#
# Returns: 0 on success, 1 if id cannot be made available.
users__get_current() {
  if [ "${1:-}" != "--no-sudo" ] && users__is_root; then
    if [ -n "${SUDO_USER:-}" ]; then
      printf '%s\n' "${SUDO_USER}"
      return 0
    fi
    if os__is_devcontainer_build; then
      if [ -n "${_REMOTE_USER:-}" ] && [ "${_REMOTE_USER}" != "root" ]; then
        printf '%s\n' "${_REMOTE_USER}"
        return 0
      fi
      [ -n "${_CONTAINER_USER:-}" ] && {
        printf '%s\n' "${_CONTAINER_USER}"
        return 0
      }
    fi
  fi
  _users__ensure_coreutils || return 1
  id -un
}

# @brief users__resolve_home [--uid] [<username-or-uid>] — Print the home directory for the given user.
#
# Resolution order:
#   1. `getent passwd` (bootstrapped if absent) — works for both usernames and
#      UIDs; also queries NSS (LDAP, NIS).
#   2. `dscl` on macOS (always available) — for Directory Services users absent from getent.
#      For a UID: resolves the username via `dscl . -search` first.
#   3. Direct `/etc/passwd` scan — last resort when the getent bootstrap failed
#      Returns empty string when the user has no entry.
#   4. Devcontainer env vars (`_REMOTE_USER_HOME` / `_CONTAINER_USER_HOME`) —
#      used when all other methods return empty; in UID mode the UID is first
#      resolved to a username via `users__username_of_uid`.
#
# When called with no positional argument, resolves the home of the current
# user via `users__get_current`.
#
# Args:
#   [--uid]   Treat the argument as a numeric UID rather than a username.
#   [<value>] Username or numeric UID. Defaults to the current user (username).
#
# Stdout: absolute path to the home directory, or empty when no entry is found.
# Returns: 0 on success, 1 if the no-arg form cannot determine the current user.
users__resolve_home() {
  local _by_uid=false
  if [[ "${1:-}" == "--uid" ]]; then
    _by_uid=true
    shift
  fi
  local _user="${1:-}" _entry="" _home
  if [[ -z "$_user" ]]; then
    _user="$(users__get_current)" || return 1
  fi
  # getent handles both username and UID, and queries NSS (LDAP, NIS).
  if _users__ensure_getent; then
    _entry="$(getent passwd "$_user" 2> /dev/null)"
    if [ -n "$_entry" ]; then
      IFS=: read -r _ _ _ _ _ _home _ <<< "$_entry"
      printf '%s\n' "$_home"
      return 0
    fi
  fi
  # macOS: users in Directory Services are absent from getent/passwd.
  if [[ "$(os__kernel)" == "Darwin" ]]; then
    local _uname="$_user"
    if [[ "$_by_uid" == true ]]; then
      _uname="$(dscl . -search /Users UniqueID "$_user" 2> /dev/null | awk 'NR==1{print $1}')"
    fi
    if [ -n "$_uname" ]; then
      _home="$(dscl . -read "/Users/${_uname}" NFSHomeDirectory 2> /dev/null | awk '{print $2}')"
      [ -n "$_home" ] && {
        printf '%s\n' "$_home"
        return 0
      }
    fi
  fi
  # Last resort: direct /etc/passwd scan when getent bootstrap failed (or dscl found nothing on macOS).
  [[ "$_by_uid" == true ]] && _home="$(awk -F: -v u="$_user" '$3==u{print $6;exit}' /etc/passwd 2> /dev/null)" ||
    _home="$(awk -F: -v u="$_user" '$1==u{print $6;exit}' /etc/passwd 2> /dev/null)"
  # Devcontainer: use the injected home env vars when all other lookups failed.
  if [ -z "$_home" ] && os__is_devcontainer_build; then
    local _uname="$_user"
    [[ "$_by_uid" == true ]] && _uname="$(users__username_of_uid "$_user" 2> /dev/null || true)"
    [ -n "$_uname" ] && [ "${_uname}" = "${_REMOTE_USER}" ] && _home="${_REMOTE_USER_HOME}"
    [ -z "$_home" ] && [ -n "$_uname" ] && [ "${_uname}" = "${_CONTAINER_USER}" ] && _home="${_CONTAINER_USER_HOME}"
  fi
  [[ "$_by_uid" == true ]] && printf '%s\n' "${_home:-}" || printf '%s\n' "${_home:-~${_user}}"
}

# @brief users__is_user_path [--uid] [<username-or-uid>] <path> — Return 0 if <path> is user-local, 1 if it is system (requires privilege).
#
# "User-local" means writable by a regular user without elevated privileges.
# Regular-user UID range is OS-specific: ≥1000 on Linux, ≥500 on macOS
# (Apple reserves 0–499 for system accounts).
# Uses the nearest existing ancestor of <path>, so the path itself need not exist yet.
#
# Without a user argument:
#   - Non-root: user-local iff the current user can write without sudo.
#   - Root: user-local iff under root's home or owned by a regular user.
#
# With a user argument, the check is against that specific user regardless of
# who is running the script:
#   - User-local iff the path is under that user's home directory, or the
#     nearest existing ancestor is owned by that user.
#
# Args:
#   [--uid]              Treat <username-or-uid> as a numeric UID rather than a username.
#   [<username-or-uid>]  User to check against. Defaults to the current user.
#   <path>               Absolute path to classify (need not exist).
#
# Returns: 0 (user-local/unprivileged), 1 (system/privileged).
users__is_user_path() {
  local _by_uid=false
  if [[ "${1:-}" == "--uid" ]]; then
    _by_uid=true
    shift
  fi
  local _p _user=""
  if [[ $# -ge 2 ]]; then
    _user="$1"
    shift
  fi
  _p="$1"
  local _existing
  _existing="$(file__nearest_existing "$_p")"
  if [[ -z "$_user" ]]; then
    # No user: runtime writability check (current user / root heuristic).
    if ! users__is_root; then
      [ -w "$_existing" ] && return 0
      return 1
    fi
    # Root: user-local iff under root's home or owned by a regular user.
    local _root_home
    _root_home="$(users__resolve_home)"
    [[ -n "$_root_home" && "$_p" == "${_root_home}/"* ]] && return 0
    local _uid _min_uid
    _uid="$(users__uid_of_path_owner "$_existing")" || return 1
    [[ "$(os__kernel)" == "Darwin" ]] && _min_uid=500 || _min_uid=1000
    ((_uid >= _min_uid && _uid < 65534)) && return 0
    return 1
  fi
  # Specific user: deterministic identity-based check.
  local _home="" _target_uid=""
  if [[ "$_by_uid" == true ]]; then
    _target_uid="$_user"
    _home="$(users__resolve_home --uid "$_user")"
  else
    _home="$(users__resolve_home "$_user")"
    _target_uid="$(users__uid_of_user "$_user" 2> /dev/null)" || true
  fi
  # Under user's home directory.
  [[ -n "$_home" && "$_p" == "${_home}/"* ]] && return 0
  # Nearest existing ancestor owned by the user.
  if [[ -n "$_target_uid" ]]; then
    local _owner_uid
    _owner_uid="$(users__uid_of_path_owner "$_existing")" || return 1
    [[ "$_owner_uid" == "$_target_uid" ]] && return 0
  fi
  return 1
}

# @brief users__add_sudoer <username> [--sudoers-dir <dir>] — Grant passwordless sudo to <username>.
#
# Writes "<username> ALL=(ALL) NOPASSWD:ALL" as a drop-in sudoers file.
# Validates the file with visudo before moving it into place; on validation
# failure the temporary file is removed and the function returns 1 without
# touching the sudoers directory. Installs sudo via ospkg if absent.
#
# Args:
#   <username>           User to grant passwordless sudo access.
#   --sudoers-dir <dir>  Drop-in directory (default: /etc/sudoers.d).
#
# Returns: 0 on success, 1 on failure.
users__add_sudoer() {
  local _username="${1:?users__add_sudoer: username is required}"
  local _sudoers_dir="/etc/sudoers.d"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sudoers-dir) _sudoers_dir="${2:?--sudoers-dir requires a value}"; shift 2 ;;
      *) logging__error "users__add_sudoer: unknown option: '$1'"; return 1 ;;
    esac
  done
  _users__ensure_sudo || return 1
  local _target="${_sudoers_dir}/${_username}" _tmp _visudo_out
  _tmp="$(mktemp)" || { logging__error "users__add_sudoer: mktemp failed."; return 1; }
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$_username" > "$_tmp"
  chmod 0440 "$_tmp"
  _visudo_out="$(users__run_privileged visudo -c -f "$_tmp" 2>&1)" || {
    rm -f "$_tmp"
    logging__error "users__add_sudoer: sudoers validation failed${_visudo_out:+: ${_visudo_out}}"
    return 1
  }
  users__run_privileged mkdir -p "$_sudoers_dir"
  users__run_privileged mv "$_tmp" "$_target"
  logging__success "Granted passwordless sudo to '${_username}'."
}
