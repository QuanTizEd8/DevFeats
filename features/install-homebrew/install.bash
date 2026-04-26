# ── Constants ────────────────────────────────────────────────────────────────
_BREW_INSTALL_BASE_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD"
_BREW_INSTALLER_URL="${_BREW_INSTALL_BASE_URL}/install.sh"
_BREW_UNINSTALLER_URL="${_BREW_INSTALL_BASE_URL}/uninstall.sh"

# ── High-level steps ──────────────────────────────────────────────────────────

install_linux_deps() {
  logging__fn_entry "install_linux_deps"
  logging__install "Installing Homebrew build dependencies."
  _linux_build_deps__install
  logging__fn_exit "install_linux_deps"
  return 0
}

run_brew_installer() {
  logging__fn_entry "run_brew_installer"
  logging__install "Running Homebrew installer as user '${RESOLVED_INSTALL_USER}'."
  local -a _env_vars=("NONINTERACTIVE=1")
  [ -n "${BREW_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_BREW_GIT_REMOTE=${BREW_GIT_REMOTE}")
  [ -n "${CORE_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_CORE_GIT_REMOTE=${CORE_GIT_REMOTE}")
  [[ "${NO_INSTALL_FROM_API}" == true ]] && _env_vars+=("HOMEBREW_NO_INSTALL_FROM_API=1")
  _env_vars+=("HOMEBREW_PREFIX=${RESOLVED_PREFIX}")
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_install.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  logging__download "Downloading Homebrew installer to '${_tmpfile}'."
  net__fetch_url_file "$_BREW_INSTALLER_URL" "$_tmpfile"
  chmod a+r "$_tmpfile"
  logging__info "Installing as '${RESOLVED_INSTALL_USER}'."
  _brew_run_as_install_user env "${_env_vars[@]}" /bin/bash "$_tmpfile"
  logging__success "Homebrew installer completed."
  logging__fn_exit "run_brew_installer"
  return 0
}

uninstall_brew() {
  logging__fn_entry "uninstall_brew"
  logging__remove "Uninstalling Homebrew at '${RESOLVED_PREFIX}'."
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_uninstall.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  net__fetch_url_file "$_BREW_UNINSTALLER_URL" "$_tmpfile"
  chmod a+r "$_tmpfile"
  # Run as the current process (root when called from root) so it can remove
  # files in a root-provisioned prefix regardless of who owns them.
  env NONINTERACTIVE=1 /bin/bash "$_tmpfile" --path "$RESOLVED_PREFIX"
  logging__success "Homebrew uninstalled."
  logging__fn_exit "uninstall_brew"
  return 0
}

export_shellenv_for_user() {
  logging__fn_entry "export_shellenv_for_user"
  local _user="$1"
  local _brew_content="$2"
  shell__sync_block \
    --files "$(shell__user_init_files --home "$(shell__resolve_home "$_user")")" \
    --marker "brew shellenv (install-homebrew)" \
    --content "$_brew_content"
  logging__fn_exit "export_shellenv_for_user"
  return 0
}

export_shellenv_main() {
  logging__fn_entry "export_shellenv_main"
  if [ "${#EXPORT_PATH[@]}" -eq 0 ]; then
    logging__info "export_path is empty; skipping shellenv export."
    logging__fn_exit "export_shellenv_main"
    return 0
  fi
  # shellcheck disable=SC2016
  local _brew_content='eval "$('"${RESOLVED_PREFIX}/bin/brew"' shellenv)"'
  local _marker="brew shellenv (install-homebrew)"
  if [ "${EXPORT_PATH[*]}" != "auto" ]; then
    shell__sync_block --files "$(printf '%s\n' "${EXPORT_PATH[@]}")" --marker "$_marker" --content "$_brew_content"
    logging__fn_exit "export_shellenv_main"
    return 0
  fi
  # auto mode
  local _is_root=false
  [ "$(id -u)" = "0" ] && _is_root=true
  if [ "$_is_root" = true ] && [ "$(os__kernel)" != "Darwin" ]; then
    logging__info "Case A: system-wide shellenv export (root + Linux)."
    shell__sync_block \
      --files "$(shell__system_path_files --profile_d "brew.sh")" \
      --marker "$_marker" \
      --content "$_brew_content"
  else
    logging__info "Case B: user-scoped shellenv export."
    export_shellenv_for_user "$RESOLVED_INSTALL_USER" "$_brew_content"
  fi
  # Resolved additional users
  local _u
  while IFS= read -r _u; do
    [[ -z "$_u" ]] && continue
    logging__info "Exporting shellenv for resolved user '${_u}'."
    export_shellenv_for_user "$_u" "$_brew_content"
  done < <(users__resolve_list)
  logging__fn_exit "export_shellenv_main"
  return 0
}

# ── Helper functions ──────────────────────────────────────────────────────────

resolve_prefix() {
  logging__fn_entry "resolve_prefix"
  local _user="$1"
  # Explicit option always wins.
  if [ -n "${PREFIX-}" ]; then
    logging__info "Using explicit prefix: '${PREFIX}'."
    echo "$PREFIX"
    logging__fn_exit "resolve_prefix"
    return 0
  fi
  # macOS: Homebrew only officially supports these two paths.
  if [ "$(os__kernel)" = "Darwin" ]; then
    if [ "$(os__arch)" = "arm64" ]; then
      echo "/opt/homebrew"
    else
      echo "/usr/local"
    fi
    logging__fn_exit "resolve_prefix"
    return 0
  fi
  # Linux: the official Homebrew installer hardcodes /home/linuxbrew/.linuxbrew
  # at startup and ignores any HOMEBREW_PREFIX env var passed to it. Using any
  # other path causes the permission check to fail for non-sudo users.
  logging__info "Using Linux default prefix: '/home/linuxbrew/.linuxbrew'."
  echo "/home/linuxbrew/.linuxbrew"
  logging__fn_exit "resolve_prefix"
  return 0
}

# Returns the path to the Homebrew/brew git repository — distinct from the
# prefix on Intel macOS and Linux, where brew lives in ${prefix}/Homebrew.
detect_brew_repository() {
  logging__fn_entry "detect_brew_repository"
  if [ "$(os__kernel)" = "Darwin" ] && [ "$(os__arch)" = "arm64" ]; then
    echo "${RESOLVED_PREFIX}"
  else
    echo "${RESOLVED_PREFIX}/Homebrew"
  fi
  logging__fn_exit "detect_brew_repository"
  return 0
}

# enforce_options — applies post-install options unconditionally:
#   • BREW_GIT_REMOTE / CORE_GIT_REMOTE: sets git remote.origin.url on the
#     brew and homebrew-core repositories, and writes env-var export blocks to
#     shell init files (so future `brew update` calls use the same remote).
#   • NO_INSTALL_FROM_API: writes / removes HOMEBREW_NO_INSTALL_FROM_API=1
#     export block in shell init files.
enforce_options() {
  logging__fn_entry "enforce_options"
  local _brew_repo _core_repo _marker_brew _marker_core _marker_api
  _brew_repo="$(detect_brew_repository)"
  _core_repo="${_brew_repo}/Library/Taps/homebrew/homebrew-core"
  _marker_brew="HOMEBREW_BREW_GIT_REMOTE (install-homebrew)"
  _marker_core="HOMEBREW_CORE_GIT_REMOTE (install-homebrew)"
  _marker_api="HOMEBREW_NO_INSTALL_FROM_API (install-homebrew)"

  # --- brew git remote ---
  if [ -n "${BREW_GIT_REMOTE-}" ]; then
    logging__info "Setting brew git remote to '${BREW_GIT_REMOTE}'."
    if [ -d "${_brew_repo}/.git" ]; then
      git -C "$_brew_repo" remote set-url origin "$BREW_GIT_REMOTE"
    else
      logging__warn "brew repository not found at '${_brew_repo}'; skipping git remote set."
    fi
  fi
  _sync_init_files "$_marker_brew" ${BREW_GIT_REMOTE:+"export HOMEBREW_BREW_GIT_REMOTE=\"${BREW_GIT_REMOTE}\""}

  # --- core git remote ---
  if [ -n "${CORE_GIT_REMOTE-}" ]; then
    logging__info "Setting homebrew-core git remote to '${CORE_GIT_REMOTE}'."
    if [ -d "${_core_repo}/.git" ]; then
      git -C "$_core_repo" remote set-url origin "$CORE_GIT_REMOTE"
    else
      logging__info "homebrew-core tap not present at '${_core_repo}'; skipping git remote set."
    fi
  fi
  _sync_init_files "$_marker_core" ${CORE_GIT_REMOTE:+"export HOMEBREW_CORE_GIT_REMOTE=\"${CORE_GIT_REMOTE}\""}

  # --- HOMEBREW_NO_INSTALL_FROM_API ---
  if [[ "${NO_INSTALL_FROM_API}" == true ]]; then
    logging__info "Persisting HOMEBREW_NO_INSTALL_FROM_API=1."
    _sync_init_files "$_marker_api" "export HOMEBREW_NO_INSTALL_FROM_API=1"
  else
    _sync_init_files "$_marker_api"
  fi

  logging__fn_exit "enforce_options"
  return 0
}

# _sync_init_files <marker> [content]
# Calls shell__sync_block for the relevant init files for RESOLVED_INSTALL_USER
# (and any resolved users) plus system-wide files when running as root on Linux.
# If content is given, writes/updates the block; if absent, removes it.
_sync_init_files() {
  local _marker="$1"
  local _content="${2-}"
  local _has_content=false
  [ $# -ge 2 ] && _has_content=true
  local _files _slug _is_root=false
  [ "$(id -u)" = "0" ] && _is_root=true

  if [ "$_is_root" = true ] && [ "$(os__kernel)" != "Darwin" ]; then
    _slug="$(echo "$_marker" | tr ' ()' '_' | tr -s '_' | tr '[:upper:]' '[:lower:]')"
    _files="$(shell__system_path_files --profile_d "${_slug}.sh")"
  else
    _files="$(shell__user_init_files --home "$(shell__resolve_home "$RESOLVED_INSTALL_USER")")"
  fi
  if [ "$_has_content" = true ]; then
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  else
    shell__sync_block --files "$_files" --marker "$_marker"
  fi

  local _u
  while IFS= read -r _u; do
    [[ -z "$_u" ]] && continue
    _files="$(shell__user_init_files --home "$(shell__resolve_home "$_u")")"
    if [ "$_has_content" = true ]; then
      shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
    else
      shell__sync_block --files "$_files" --marker "$_marker"
    fi
  done < <(users__resolve_list)
  return 0
}

# _brew_run_as_install_user <cmd> [args...]
# Run a command as RESOLVED_INSTALL_USER when the current process is root and
# the install user is not root. Uses runuser(1) on Linux (no sudo config
# needed for root) and sudo on macOS (runuser is absent there).
_brew_run_as_install_user() {
  logging__fn_entry "_brew_run_as_install_user"
  if [ "$(id -u)" != "0" ] || [ "${RESOLVED_INSTALL_USER}" = "root" ]; then
    "$@"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    sudo -u "${RESOLVED_INSTALL_USER}" "$@"
  else
    runuser -u "${RESOLVED_INSTALL_USER}" -- "$@"
  fi
  logging__fn_exit "_brew_run_as_install_user"
  return 0
}

resolve_install_user() {
  logging__fn_entry "resolve_install_user"
  # 1. Explicit option always wins (validation happens separately).
  if [ -n "${INSTALL_USER-}" ]; then
    logging__info "Using specified install_user: '${INSTALL_USER}'."
    echo "$INSTALL_USER"
    logging__fn_exit "resolve_install_user"
    return 0
  fi
  # 2. Non-root caller: always use self.
  if [ "$(id -u)" != "0" ]; then
    id -nu
    logging__fn_exit "resolve_install_user"
    return 0
  fi
  # 3. Root on macOS: must find a non-root user; root installs are forbidden.
  if [ "$(os__kernel)" = "Darwin" ]; then
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
      logging__info "macOS root: using SUDO_USER='${SUDO_USER}' as install_user."
      echo "$SUDO_USER"
    else
      local _u
      _u="$(dscl . list /Users 2> /dev/null |
        grep -v -E '^(_|daemon|nobody|root|Guest)' |
        head -1)" || true
      if [ -n "$_u" ]; then
        logging__info "macOS root: using first non-system user '${_u}' as install_user."
        echo "$_u"
      else
        logging__error "Running as root on macOS but no non-root user found."
        logging__info "Set the 'install_user' option to a non-root user account."
        exit 1
      fi
    fi
    logging__fn_exit "resolve_install_user"
    return 0
  fi
  # 4. Root on Linux: use SUDO_USER when set (bare-metal sudo invocation),
  # otherwise fall back to 'linuxbrew'. _REMOTE_USER is intentionally NOT used
  # here — the official Homebrew installer hardcodes /home/linuxbrew/.linuxbrew
  # and ignores HOMEBREW_PREFIX on Linux, so a remoteUser-derived prefix would
  # fail the installer's permission check. Shellenv export for _REMOTE_USER is
  # handled separately by export_shellenv_main via add_remote_user.
  if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
    logging__info "Linux root: using SUDO_USER='${SUDO_USER}' as install_user."
    echo "$SUDO_USER"
  else
    logging__info "Linux root: falling back to 'linuxbrew' as install_user."
    echo "linuxbrew"
  fi
  logging__fn_exit "resolve_install_user"
  return 0
}

validate_install_user() {
  logging__fn_entry "validate_install_user"
  local _user="$1"
  # Non-root caller cannot impersonate another user.
  if [ "$(id -u)" != "0" ] && [ "$_user" != "$(id -nu)" ]; then
    logging__error "install_user='${_user}' differs from the current user '$(id -nu)'."
    logging__info "Only root can install Homebrew for a different user."
    exit 1
  fi
  # macOS: root is never a valid Homebrew owner.
  if [ "$(os__kernel)" = "Darwin" ] && [ "$_user" = "root" ]; then
    logging__error "The Homebrew installer refuses to run as root on macOS."
    logging__info "Set 'install_user' to a non-root user account."
    exit 1
  fi
  # Linux: root is allowed only when explicitly requested; warn about reliability.
  if [ "$(os__kernel)" != "Darwin" ] && [ "$_user" = "root" ]; then
    logging__warn "install_user='root' on Linux: the official Homebrew installer may refuse"
    logging__info "root in some container environments (Docker BuildKit + cgroup v2)."
    logging__info "Consider using a non-root install_user."
  fi
  # Target user must already exist (except 'linuxbrew', created later if needed).
  if [ "$_user" != "linuxbrew" ] && [ "$_user" != "root" ] && ! id "$_user" &> /dev/null; then
    logging__error "install_user='${_user}' does not exist on this system."
    exit 1
  fi
  logging__fn_exit "validate_install_user"
  return 0
}

# prepare_prefix_if_needed <prefix> <install_user>
# Linux + root only: creates the linuxbrew system user if needed, then ensures
# the prefix directory exists and is owned by the install user.
# No-op on macOS (the Homebrew installer manages /opt/homebrew and /usr/local).
# No-op when not running as root (target user is responsible for their own home).
prepare_prefix_if_needed() {
  logging__fn_entry "prepare_prefix_if_needed"
  local _prefix="$1" _user="$2"
  # Create the linuxbrew system user if it does not yet exist.
  if [ "$_user" = "linuxbrew" ] && ! id linuxbrew &> /dev/null; then
    logging__info "Creating 'linuxbrew' system user."
    useradd --create-home --shell /bin/bash linuxbrew
    # Ubuntu 22.04+ creates home directories with mode 750; make the home
    # world-traversable so other users can reach the brew binary.
    chmod 755 /home/linuxbrew
  fi
  # Create the prefix directory if it does not exist yet.
  if [ ! -e "$_prefix" ]; then
    logging__info "Creating prefix directory '${_prefix}' owned by '${_user}'."
    mkdir -p "$_prefix"
    chmod 755 "$(dirname "$_prefix")" 2> /dev/null || true
    chown "$_user" "$_prefix"
    logging__fn_exit "prepare_prefix_if_needed"
    return 0
  fi
  # Prefix already exists — inspect ownership.
  local _owner
  _owner="$(stat -c '%U' "$_prefix" 2> /dev/null || echo '')"
  if [ "$_owner" = "$_user" ]; then
    logging__info "Prefix '${_prefix}' already owned by '${_user}'."
    logging__fn_exit "prepare_prefix_if_needed"
    return 0
  fi
  # A brew binary is present: ownership mismatch is handled by if_exists.
  if [ -f "${_prefix}/bin/brew" ]; then
    logging__warn "Prefix '${_prefix}' is owned by '${_owner}' (not '${_user}')."
    logging__info "Existing installation will be handled by if_exists='${IF_EXISTS}'."
    logging__fn_exit "prepare_prefix_if_needed"
    return 0
  fi
  # Empty directory: safe to re-own.
  if [ -z "$(ls -A "$_prefix" 2> /dev/null)" ]; then
    logging__info "Re-owning empty prefix '${_prefix}' to '${_user}'."
    chown "$_user" "$_prefix"
    logging__fn_exit "prepare_prefix_if_needed"
    return 0
  fi
  # Non-empty directory owned by someone else with no brew binary — conflict.
  logging__error "Prefix '${_prefix}' is non-empty and owned by '${_owner}' (not '${_user}')."
  logging__info "Remove or empty the directory first, or set a different prefix."
  exit 1
}

# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"

# ── Resolve install user, then derive prefix from that user ──────────────────
RESOLVED_INSTALL_USER="$(resolve_install_user)"
logging__info "Install user: '${RESOLVED_INSTALL_USER}'."
validate_install_user "$RESOLVED_INSTALL_USER"
RESOLVED_PREFIX="$(resolve_prefix "$RESOLVED_INSTALL_USER")"
logging__info "Prefix: '${RESOLVED_PREFIX}'."
if [ "$(os__kernel)" != "Darwin" ] && [ "$(id -u)" = "0" ]; then
  prepare_prefix_if_needed "$RESOLVED_PREFIX" "$RESOLVED_INSTALL_USER"
fi

# ── Step 1: Linux build dependencies ─────────────────────────────────────────
if [ "$(os__kernel)" != "Darwin" ]; then
  install_linux_deps
fi

# ── Step 2: Install / skip / reinstall Homebrew ───────────────────────────────
_BREW_EXEC="${RESOLVED_PREFIX}/bin/brew"
if [ -f "$_BREW_EXEC" ]; then
  logging__warn "Homebrew found at '${_BREW_EXEC}'."
  case "$IF_EXISTS" in
    skip)
      logging__info "if_exists=skip: existing Homebrew detected; skipping installer and continuing to post-install steps."
      ;;
    fail)
      logging__error "if_exists=fail: Homebrew already installed at '${RESOLVED_PREFIX}'."
      logging__info "Remove it first or set if_exists=skip or if_exists=reinstall."
      exit 1
      ;;
    reinstall)
      logging__info "if_exists=reinstall: uninstalling then reinstalling Homebrew."
      uninstall_brew
      run_brew_installer
      ;;
    *)
      logging__error "Invalid value for 'if_exists': '${IF_EXISTS}'. Use 'skip', 'fail', or 'reinstall'."
      exit 1
      ;;
  esac
else
  run_brew_installer
fi

# ── Step 3: Verify brew executable ───────────────────────────────────────────
if [ ! -f "$_BREW_EXEC" ]; then
  logging__error "Homebrew executable not found at '${_BREW_EXEC}' after installation."
  exit 1
fi
logging__success "Homebrew $("$_BREW_EXEC" --version | head -1) is available at '${_BREW_EXEC}'."

# ── Step 3.5: Enforce options (git remotes, NO_INSTALL_FROM_API) ──────────────
# Runs unconditionally so options are applied even when if_exists=skip.
enforce_options

# ── Step 4: brew update ───────────────────────────────────────────────────────
if [[ "$UPDATE" == true ]]; then
  logging__info "Running 'brew update'."
  _brew_run_as_install_user "$_BREW_EXEC" update
  logging__success "brew update completed."
fi

# ── Step 5: Export shellenv ───────────────────────────────────────────────────
export_shellenv_main

# ── Step 6: brew doctor (warn only) ──────────────────────────────────────────
logging__info "Running 'brew doctor' (warnings only)."
_brew_run_as_install_user "$_BREW_EXEC" doctor 2>&1 || true

# ── Step 7: Write-permission group ───────────────────────────────────────────
if [[ -n "${WRITE_GROUP:-}" ]] && [[ "$(os__kernel)" = "Linux" ]]; then
  export ADD_CURRENT_USER ADD_REMOTE_USER ADD_CONTAINER_USER ADD_USERS
  mapfile -t _write_users < <(users__resolve_list)
  users__set_write_permissions "$RESOLVED_PREFIX" "$RESOLVED_INSTALL_USER" "$WRITE_GROUP" "${_write_users[@]}"
fi
