#!/usr/bin/env bash
# User management: resolve users, set login shells, manage installation prefixes.
#
# Provides helpers for detecting root, resolving the remote user list from
# devcontainer env vars, managing file permissions, and setting the login shell
# for one or more users. Works on Alpine (patching PAM), Debian-based, and macOS.

[ -n "${_USERS__LIB_LOADED-}" ] && return 0
_USERS__LIB_LOADED=1

_USERS__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_USERS__LIB_DIR/ospkg.sh"

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

# @brief users__resolve_list — Print one deduplicated username per line from devcontainer user-config env vars.
#
# Root is excluded from auto-detected paths (SUDO_USER, _REMOTE_USER,
# _CONTAINER_USER) when other non-root users exist, because the build process
# running as root should not override a named container user. When the build
# user IS root and no other users are found, root is included as a fallback
# (e.g. plain container images, standalone macOS use). Root is always
# accepted in ADD_USERS.
#
# Env:
#   ADD_CURRENT_USER    "true" to include SUDO_USER / whoami (default: true).
#   ADD_REMOTE_USER     "true" to include _REMOTE_USER (default: true).
#   ADD_CONTAINER_USER  "true" to include _CONTAINER_USER (default: true).
#   ADD_USERS           Extra usernames (bash array, newline-delimited, or comma-separated); root allowed.
#
# Stdout: one username per line.
users__resolve_list() {
  # Track seen names in a local space-separated string for dedup.
  local _seen=""
  local _out=""
  local _raw_add_users="${ADD_USERS-}"

  logging__info "users__resolve_list: inputs ADD_CURRENT_USER='${ADD_CURRENT_USER:-true}' ADD_REMOTE_USER='${ADD_REMOTE_USER:-true}' ADD_CONTAINER_USER='${ADD_CONTAINER_USER:-true}' SUDO_USER='${SUDO_USER-}' _REMOTE_USER='${_REMOTE_USER-}' _CONTAINER_USER='${_CONTAINER_USER-}' _REMOTE_USER_HOME='${_REMOTE_USER_HOME-}' _CONTAINER_USER_HOME='${_CONTAINER_USER_HOME-}' ADD_USERS='${_raw_add_users}'"

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

  # Accept both newline and comma separators in scalar values.
  _users_add_from_text() {
    local _raw="$1"
    [ -z "$_raw" ] && return 0

    local _normalized _old_ifs _extra
    _normalized="$(printf '%s\n' "$_raw" | tr ',' '\n')"
    _old_ifs="$IFS"
    IFS='
'
    for _extra in $_normalized; do
      # Trim leading/trailing spaces.
      _extra="${_extra#"${_extra%%[! ]*}"}"
      _extra="${_extra%"${_extra##*[! ]}"}"
      _users_add "$_extra"
    done
    IFS="$_old_ifs"
    return 0
  }

  # Auto-detected users: root is deferred — only added as a fallback when
  # no other user is found.  In a devcontainer with a remoteUser/containerUser
  # the build runs as root, but configuration should target the named user, not
  # root.  When there is genuinely no other user (e.g. a plain container image
  # with no remoteUser or a standalone macOS install), root is the intended
  # target and should be included.
  local _root_queued=false
  if [ "${ADD_CURRENT_USER:-true}" = "true" ]; then
    local _cur
    _cur="$(users__get_current)"
    if [ "$_cur" != "root" ]; then
      _users_add "$_cur"
    else
      _root_queued=true
    fi
  fi

  if [ "${ADD_REMOTE_USER:-true}" = "true" ] && [ -n "${_REMOTE_USER:-}" ]; then
    [ "${_REMOTE_USER}" != "root" ] && _users_add "${_REMOTE_USER}"
  fi

  if [ "${ADD_CONTAINER_USER:-true}" = "true" ] && [ -n "${_CONTAINER_USER:-}" ]; then
    [ "${_CONTAINER_USER}" != "root" ] && _users_add "${_CONTAINER_USER}"
  fi

  # ADD_USERS: explicit override list — root is allowed if deliberately
  # specified (e.g. configuring Podman rootless for the root user).
  # The generated argparse header provides arrays in bash; support that first,
  # then fall back to scalar parsing for POSIX sh callers.
  if [ -n "${ADD_USERS:-}" ]; then
    if [ -n "${BASH_VERSION-}" ]; then
      local _bash_items
      # In bash, this safely serialises both scalar and array values.
      _bash_items="$(eval 'printf "%s\n" "${ADD_USERS[@]}"' 2> /dev/null || true)"
      _users_add_from_text "$_bash_items"
    else
      _users_add_from_text "${ADD_USERS}"
    fi
  fi

  # Root fallback: if the build user was root and no other users were resolved,
  # include root so the feature has a target to configure.
  if [ "$_root_queued" = "true" ] && [ -z "$_out" ]; then
    _users_add "root"
  fi

  # Log final result (or explicit empty marker) to aid CI troubleshooting.
  if [ -n "$_out" ]; then
    logging__info "users__resolve_list: resolved users='${_out# }'"
  else
    logging__info "users__resolve_list: resolved users='(empty)'"
  fi

  # Print one name per line (strip leading space from _out).
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
    dseditgroup -o read "$_group" > /dev/null 2>&1 || dseditgroup -o create -q "$_group"
    local _u
    for _u in "$@"; do
      [ -z "$_u" ] && continue
      dseditgroup -o checkmember -m "$_u" "$_group" > /dev/null 2>&1 ||
        dseditgroup -o edit -a "$_u" -t user "$_group"
    done
  else
    if ospkg__run --manifest "$_USERS__SHADOW_UTILS_MANIFEST" --build-group "lib-users" --skip_installed; then
      getent group "$_group" > /dev/null 2>&1 || groupadd -r "$_group"
      local _u
      for _u in "$@"; do
        [ -z "$_u" ] && continue
        id -nG "$_u" 2> /dev/null | grep -qw "$_group" && continue
        if command -v usermod > /dev/null 2>&1; then
          usermod -a -G "$_group" "$_u"
        else
          logging__warn "usermod not found — cannot add '${_u}' to group '${_group}'."
        fi
      done
    else
      logging__warn "Neither dseditgroup nor groupadd found — skipping group setup."
    fi
  fi
  chown -R "${_owner}:${_group}" "$_path"
  chmod -R g+rwX "$_path"
  find "$_path" -type d -print0 | xargs -0 chmod g+s
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
    if chmod u+s "$_path"; then
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
  [ -f "$_file" ] || { printf '%s\n' "$_max"; return 0; }
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
    echo "$_shell" >> "$_shells_file"
    logging__info "Added '${_shell}' to '${_shells_file}'."
  fi

  # Alpine PAM: chsh requires a password even when run as root unless
  # pam_rootok.so is listed as sufficient.
  if [ -f /etc/pam.d/chsh ]; then
    if ! grep -Eq '^auth[[:blank:]]+sufficient[[:blank:]]+pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
      if grep -Eq '^auth(.*)pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
        awk '/^auth(.*)pam_rootok\.so$/ { $2 = "sufficient" } { print }' \
          /etc/pam.d/chsh > /tmp/_chsh.tmp && mv /tmp/_chsh.tmp /etc/pam.d/chsh
      else
        printf 'auth sufficient pam_rootok.so\n' >> /etc/pam.d/chsh
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
    if chsh -s "$_shell" "$_username" 2> /dev/null; then
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
  "${_cmd[@]}"
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
