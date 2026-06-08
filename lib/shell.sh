# shellcheck shell=bash
# Shell startup file helpers: detect, read, and write login shell configuration.
#
# Provides helpers for detecting system-wide and per-user startup files,
# writing idempotent named config blocks, and resolving `ZDOTDIR` for zsh.
# Supports bash, zsh, and login-shell path configuration.

# Shared awk helpers used by shell__write_block and shell__sync_block.
# norm() strips BOM, leading/trailing whitespace, and CR; is_blank_line() tests for empty.
_SHELL__AWK_NORM='
  function norm(l) {
    if (length(l) >= 3 && substr(l, 1, 3) == "\357\273\277") l = substr(l, 4)
    sub(/^[[:space:]]+/, "", l)
    sub(/\r$/, "", l)
    sub(/[[:space:]]+$/, "", l)
    return l
  }
  function is_blank_line(l) { return norm(l) == "" }
'

read -r -d '' _SHELL__BINUTILS_MANIFEST << 'EOF' || true
packages:
  - when: {kernel: linux}
    packages: [binutils]
EOF

# _shell__ensure_strings (internal) — Attempt to install binutils so strings is available.
# Returns 0 when strings is on PATH (before or after install), 1 otherwise (non-fatal).
_shell__ensure_strings() {
  command -v strings > /dev/null 2>&1 && return 0
  ospkg__run --manifest "$_SHELL__BINUTILS_MANIFEST" --build-group "lib-shell" || true
  command -v strings > /dev/null 2>&1 && return 0
  logging__warn "'strings' not available; falling back to os-release detection."
  return 1
}

# @brief shell__bash — Run the active bash binary.
# Uses _BASH_BIN set by install.sh bootstrap when available; otherwise falls back to bash on PATH.
shell__bash() { "${_BASH_BIN:-bash}" "$@"; }

# @brief shell__detect_bashrc — Print the system-wide bashrc path for the current distro.
#
# Uses os-release platform IDs. Never uses file-existence checks — a file at
# the wrong path for this distro won't be sourced by any shell.
#
# Stdout: one of `/etc/bash.bashrc`, `/etc/bashrc`, or `/etc/bash/bashrc`.
shell__detect_bashrc() {
  case "$(os__platform)" in
    alpine)
      echo "/etc/bash/bashrc"
      return 0
      ;;
    rhel | suse | macos)
      echo "/etc/bashrc"
      return 0
      ;;
  esac
  echo "/etc/bash.bashrc"
  return 0
}

# @brief shell__detect_zshdir — Print the system-wide zsh config directory (`/etc/zsh` or `/etc`). Uses binary probing, never directory-existence checks.
#
# Detection order: (1) strings-probe the zsh binary (zsh compiles in the
# path of its global zshenv); (2) os-release platform IDs. Never uses
# directory-existence checks — a directory at the wrong path won't be used
# by the shell anyway.
#
# Stdout: `/etc/zsh` (most distros) or `/etc` (Fedora/RHEL, openSUSE, macOS).
shell__detect_zshdir() {
  # Ask zsh which global zshenv path it was compiled with.
  local _compiled
  _shell__ensure_strings || true
  _compiled="$(strings "$(command -v zsh 2> /dev/null)" 2> /dev/null |
    grep -m1 -E '^/etc/(zsh/)?zshenv$' || true)"
  if [ -n "$_compiled" ]; then
    dirname "$_compiled"
    return 0
  fi
  # os__platform fallback.
  case "$(os__platform)" in
    rhel | suse | macos)
      echo "/etc"
      return 0
      ;;
  esac
  echo "/etc/zsh"
  return 0
}

# @brief shell__write_block --file <f> --marker <id> --content <c> — Idempotently write a named `# >>> <id> >>>` … `# <<< <id> <<<` block to a file. Creates the file if needed.
#
# Updates the block in-place if the marker already exists; appends otherwise.
# Creates parent directories and the file if they do not exist.
# Blank lines: one empty line below every block; one empty line above unless the
# begin marker would be the first line of the file (append or in-place update).
#
# Args:
#   --file <f>     Path to the target file.
#   --marker <id>  Block identifier used in the begin/end comment markers.
#   --content <c>  Content to write inside the block.
shell__write_block() {
  local _file="" _marker="" _content="" _lb=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --file)
        shift
        _file="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _begin="# >>> ${_marker} >>>"
  local _end="# <<< ${_marker} <<<"
  file__mkdir "$(dirname "$_file")"
  if [[ ! -f "$_file" ]]; then
    printf '' | file__tee "$_file"
  fi
  if grep -qF "$_begin" "$_file"; then
    # Normalize marker lines before comparing: hosted macOS ~/.bash_profile often
    # uses CRLF; some images also add a UTF-8 BOM and/or leading whitespace on
    # continued lines. grep -qF still finds the marker substring, but raw $0
    # equality with begin/end would otherwise never match.
    #
    # Formatting: one blank line above the block when it is not the first line
    # in the file (unless a blank line is already there); one blank line below.
    local _tmp
    _tmp="$(mktemp)"
    awk -v begin="$_begin" -v end="$_end" -v content="$_content" "$_SHELL__AWK_NORM"'
      BEGIN { last_blank = 1 }
      norm($0) == begin {
        if (NR > 1 && !last_blank) print ""
        print begin
        print content
        found = 1
        next
      }
      found && norm($0) == end {
        print end
        print ""
        last_blank = 1
        found = 0
        next
      }
      found { next }
      { print; last_blank = is_blank_line($0) }
    ' "$_file" > "$_tmp" && file__cp "$_tmp" "$_file"
    rm -f "$_tmp"
    logging__info "Updated shell block '${_marker}' in '${_file}'."
  else
    # Begin marker starts on its own line. Surround with blank lines: none above
    # when the block is the entire file; otherwise one empty line above (after
    # ensuring the file ends with a newline) and one empty line below.
    if [ -f "$_file" ] && [ -s "$_file" ]; then
      _lb="$(tail -c1 "$_file" 2> /dev/null || printf '')"
      if [ "$_lb" != "$(printf '\n')" ]; then
        printf '\n' | file__tee --append "$_file"
      fi
      printf '\n%s\n%s\n%s\n\n' "$_begin" "$_content" "$_end" | file__tee --append "$_file"
    else
      printf '%s\n%s\n%s\n\n' "$_begin" "$_content" "$_end" | file__tee --append "$_file"
    fi
    logging__success "Appended shell block '${_marker}' to '${_file}'."
  fi
  return 0
}

# @brief shell__sync_block --files <list> --marker <id> [--content <c>] — Write (if `--content` given) or remove the named block in each file in the newline-separated list.
#
# For each file in the newline-separated <files> list:
#   - If --content is given: write or update the named idempotency block.
#   - If --content is absent: remove the named idempotency block if present.
# Skips blank lines in the file list.
#
# Args:
#   --files <list>  Newline-separated list of file paths.
#   --marker <id>   Block identifier (same format as shell__write_block).
#   --content <c>   Block content (optional; omit to remove the block).
shell__sync_block() {
  local _files="" _marker="" _content="" _has_content=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --files)
        shift
        _files="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        _has_content=true
        shift
        ;;
      *) shift ;;
    esac
  done
  local _begin="# >>> ${_marker} >>>"
  local _end="# <<< ${_marker} <<<"
  local _f
  while IFS= read -r _f; do
    [ -z "$_f" ] && continue
    if [ "$_has_content" = true ]; then
      shell__write_block --file "$_f" --marker "$_marker" --content "$_content"
    else
      [ -f "$_f" ] || continue
      grep -qF "$_begin" "$_f" || continue
      awk -v begin="$_begin" -v end="$_end" "$_SHELL__AWK_NORM"'
        norm($0) == begin { found=1; next }
        found && norm($0) == end { found=0; next }
        found { next }
        { print }
      ' "$_f" > "${_f}.tmp" && mv "${_f}.tmp" "$_f"
      logging__remove "Removed shell block '${_marker}' from '${_f}'."
    fi
  done <<< "$_files"
  return 0
}

# @brief shell__user_login_file [--home <dir>] — Print the bash login startup file path (`~/.bash_profile`, `~/.bash_login`, or `~/.profile`). Falls back to `~/.bash_profile`.
#
# Probes in order: .bash_profile, .bash_login, .profile. Falls back to
# <home>/.bash_profile if none exist yet.
#
# Args:
#   --home <dir>  User home directory (default: $HOME).
#
# Stdout: absolute path to the login file.
shell__user_login_file() {
  local _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _f
  for _f in "${_home}/.bash_profile" "${_home}/.bash_login" "${_home}/.profile"; do
    [ -f "$_f" ] && {
      echo "$_f"
      return 0
    }
  done
  echo "${_home}/.bash_profile"
  return 0
}

# @brief shell__system_path_files [--profile_d <filename>] — Print system-wide shell startup file paths for PATH/env injection.
#
# Intended for use when configuring PATH or environment variables as root
# on Linux. Prints one path per line:
# BASH_ENV file (via shell__ensure_bashenv); /etc/profile.d/<f> (if --profile_d given); global bashrc; <zshdir>/zshenv.
#
# Args:
#   --profile_d <filename>  Base filename for an /etc/profile.d/ drop-in (optional).
#
# Stdout: one path per line for each applicable shell startup file.
shell__system_path_files() {
  local _profiled=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --profile_d)
        shift
        _profiled="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  shell__ensure_bashenv
  [ -n "$_profiled" ] && echo "/etc/profile.d/${_profiled}"
  shell__detect_bashrc
  echo "$(shell__detect_zshdir)/zshenv"
  return 0
}

# @brief shell__detect_zdotdir [--home <dir>] [--user <username>] — Print the effective ZDOTDIR for a user. Probes the live environment, parses system and user zshenv, then falls back to `<home>`.
#
# Detection order:
#   1. If --user is given and is a different user and zsh is available:
#      run `zsh` as that user to read ZDOTDIR from the live environment.
#   2. If <home> matches $HOME and $ZDOTDIR is set → use $ZDOTDIR directly
#      (we are the target user; the value is live in the current environment).
#   3. Parse ZDOTDIR= assignments from the system zshenv and <home>/.zshenv.
#      Substitutes $HOME, ${HOME}, ~, $XDG_CONFIG_HOME, ${XDG_CONFIG_HOME}.
#      Falls back to the next tier if the result still contains unresolvable variables.
#   4. Falls back to <home>.
#
# Args:
#   --home <dir>      User home directory (default: $HOME).
#   --user <username> Target username. When given and differs from the current
#                     user, spawns zsh as that user to read the live ZDOTDIR.
#
# Stdout: absolute path to the effective ZDOTDIR.
shell__detect_zdotdir() {
  local _home="${HOME:-}" _user=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --user)
        shift
        _user="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  # Tier 1: run zsh as the target user to get the live ZDOTDIR.
  # Only when a username is given, it differs from the current user, and zsh
  # is available.
  if [[ -n "$_user" && "$_user" != "$(users__get_current --no-sudo 2> /dev/null)" ]] &&
    command -v zsh > /dev/null 2>&1; then
    local _live_zdotdir=""
    # shellcheck disable=SC2016  # ZDOTDIR is a zsh variable, not a bash variable
    _live_zdotdir="$(users__run_as "$_user" -- zsh -c 'printf "%s" "${ZDOTDIR:-}"' \
      2> /dev/null || true)"
    if [[ -n "$_live_zdotdir" ]]; then
      echo "$_live_zdotdir"
      return 0
    fi
  fi

  # Tier 2: live environment — we ARE the target user.
  if [[ "$_home" == "${HOME:-}" && -n "${ZDOTDIR:-}" ]]; then
    echo "$ZDOTDIR"
    return 0
  fi

  # Tier 3: parse ZDOTDIR= from zshenv files.
  local _zshenv_files=""
  local _sys_zshenv
  _sys_zshenv="$(shell__detect_zshdir)/zshenv"
  [[ -f "$_sys_zshenv" ]] && _zshenv_files="$_sys_zshenv"
  [[ -f "${_home}/.zshenv" ]] && _zshenv_files="${_zshenv_files:+${_zshenv_files}
}${_home}/.zshenv"

  if [[ -n "$_zshenv_files" ]]; then
    local _val="" _f
    while IFS= read -r _f; do
      [[ -z "$_f" ]] && continue
      # Match last ZDOTDIR= assignment (last wins, like shell evaluation).
      # Strips optional 'export ', quotes, and trailing comments.
      # Uses [[:space:]] instead of \s for macOS sed compatibility.
      _val="$(grep -E '^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=' "$_f" 2> /dev/null | tail -1 |
        sed -E 's/^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=//; s/^["'"'"']//; s/["'"'"'][[:space:]]*(#.*)?$//; s/[[:space:]]*#.*//')" || true
      # Keep iterating — user .zshenv overrides system zshenv.
    done <<< "$_zshenv_files"
    if [[ -n "$_val" ]]; then
      # Substitute known variables with concrete values.
      local _xdg="${XDG_CONFIG_HOME:-${_home}/.config}"
      _val="${_val//\$\{XDG_CONFIG_HOME\}/$_xdg}"
      _val="${_val//\$XDG_CONFIG_HOME/$_xdg}"
      _val="${_val//\$\{HOME\}/$_home}"
      _val="${_val//\$HOME/$_home}"
      _val="${_val/#\~/$_home}"
      # If unresolvable variables remain, fall back to <home>.
      if [[ "$_val" == *'$'* ]]; then
        echo "$_home"
        return 0
      fi
      echo "$_val"
      return 0
    fi
  fi

  # Tier 4: fallback.
  echo "$_home"
  return 0
}

# @brief shell__detect_xdg_config_home [<username>] — Print the effective XDG_CONFIG_HOME for a user.
#
# Detection order:
#   1. If a username is given and differs from the current user and bash is
#      available: run `bash` as that user to read XDG_CONFIG_HOME from the
#      live environment.
#   2. If no username (or same as current user) and $XDG_CONFIG_HOME is set
#      in the current environment → use it directly.
#   3. Falls back to `<home>/.config`.
#
# Args:
#   <username>  (optional positional) Target username. Home is resolved via
#               users__resolve_home. Defaults to the current user.
#
# Stdout: absolute path to the effective XDG_CONFIG_HOME.
shell__detect_xdg_config_home() {
  local _user="${1:-}" _home
  if [[ -n "$_user" ]]; then
    _home="$(users__resolve_home "$_user")"
  else
    _home="${HOME:-}"
  fi

  # Tier 1: run bash as the target user to get the live XDG_CONFIG_HOME.
  if [[ -n "$_user" && "$_user" != "$(users__get_current --no-sudo 2> /dev/null)" ]] &&
    command -v "${_BASH_BIN:-bash}" > /dev/null 2>&1; then
    local _live_xdg=""
    # shellcheck disable=SC2016  # XDG_CONFIG_HOME is a variable for the target user's shell
    _live_xdg="$(users__run_as "$_user" -- "${_BASH_BIN:-bash}" -c 'printf "%s" "${XDG_CONFIG_HOME:-}"' \
      2> /dev/null || true)"
    if [[ -n "$_live_xdg" ]]; then
      echo "$_live_xdg"
      return 0
    fi
  fi

  # Tier 2: live environment — we ARE the target user.
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    echo "$XDG_CONFIG_HOME"
    return 0
  fi

  # Tier 3: fallback.
  echo "${_home}/.config"
  return 0
}

# @brief shell__resolve_zsh_theme_file [<username>] [--zdotdir <dir>] --source-marker <marker>
#
# Resolves the path of the per-user Zsh theme file (`zshtheme`) and ensures it
# is wired into the user's `.zshrc` via a sourced block.
#
# Detects ZDOTDIR (via --zdotdir override or shell__detect_zdotdir) and returns
# `$ZDOTDIR/zshtheme`. When the theme file does not already exist, a guarded
# source block is injected into `$ZDOTDIR/.zshrc` (created if absent) using
# --source-marker so that `.zshrc` sources the theme file on startup.
#
# Call this only when no user-provided path override is in effect; handle that
# check at the call site before invoking this function.
#
# Args:
#   <username>          (optional positional) Target username. Home resolved via
#                       users__resolve_home. Defaults to current user.
#   --zdotdir <dir>     ZDOTDIR override (skips live detection when given).
#   --source-marker <m> Marker for the shell__write_block source-injection block.
#
# Stdout: absolute path to the theme file to write the feature block into.
shell__resolve_zsh_theme_file() {
  local _user="" _zdotdir_override="" _source_marker=""
  # Consume the optional leading positional username only when the first arg is
  # not a flag (does not start with '--').
  if [[ $# -gt 0 && "$1" != --* ]]; then
    _user="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case $1 in
      --zdotdir)
        shift
        _zdotdir_override="$1"
        shift
        ;;
      --source-marker)
        shift
        _source_marker="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  local _home
  if [[ -n "$_user" ]]; then
    _home="$(users__resolve_home "$_user")"
  else
    _home="${HOME:-}"
  fi

  local _zdotdir
  if [[ -n "$_zdotdir_override" ]]; then
    _zdotdir="$_zdotdir_override"
  else
    _zdotdir="$(shell__detect_zdotdir --user "$_user" --home "$_home")"
  fi

  local _theme_file="${_zdotdir}/zshtheme"
  if [[ ! -f "$_theme_file" ]]; then
    # shellcheck disable=SC2016  # ZDOTDIR/$HOME are runtime shell variables, not bash variables
    shell__write_block \
      --file "${_zdotdir}/.zshrc" \
      --marker "$_source_marker" \
      --content '[ -f "${ZDOTDIR:-$HOME}/zshtheme" ] && source "${ZDOTDIR:-$HOME}/zshtheme"'
  fi

  echo "$_theme_file"
  return 0
}

# @brief shell__resolve_bash_theme_file [<username>] --source-marker <marker>
#
# Resolves the path of the per-user Bash theme file (`bashtheme`) and ensures it
# is wired into the user's `.bashrc` via a sourced block.
#
# Detects XDG_CONFIG_HOME (via shell__detect_xdg_config_home) and returns
# `$XDG_CONFIG_HOME/bash/bashtheme`. When the theme file does not already exist,
# a guarded source block is injected into `$HOME/.bashrc` (created if absent)
# using --source-marker.
#
# Call this only when no user-provided path override is in effect; handle that
# check at the call site before invoking this function.
#
# Args:
#   <username>          (optional positional) Target username. Home resolved via
#                       users__resolve_home. Defaults to current user.
#   --source-marker <m> Marker for the shell__write_block source-injection block.
#
# Stdout: absolute path to the theme file to write the feature block into.
shell__resolve_bash_theme_file() {
  local _user="" _source_marker=""
  # Consume the optional leading positional username only when the first arg is
  # not a flag (does not start with '--').
  if [[ $# -gt 0 && "$1" != --* ]]; then
    _user="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case $1 in
      --source-marker)
        shift
        _source_marker="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  local _home
  if [[ -n "$_user" ]]; then
    _home="$(users__resolve_home "$_user")"
  else
    _home="${HOME:-}"
  fi

  local _xdg_config_home
  _xdg_config_home="$(shell__detect_xdg_config_home "$_user")"

  local _theme_file="${_xdg_config_home}/bash/bashtheme"
  if [[ ! -f "$_theme_file" ]]; then
    # shellcheck disable=SC2016  # XDG_CONFIG_HOME/$HOME are runtime shell variables, not bash variables
    shell__write_block \
      --file "${_home}/.bashrc" \
      --marker "$_source_marker" \
      --content '[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme"'
  fi

  echo "$_theme_file"
  return 0
}

# @brief shell__user_path_files [--home <dir>] [--zdotdir <dir>] — Print user startup file paths for a PATH export: bash login file, `.bashrc`, and `<zdotdir>/.zshenv`.
#
# Args:
#   --home <dir>    User home directory (default: `$HOME`).
#   --zdotdir <dir> ZDOTDIR override (default: auto-detected via `shell__detect_zdotdir`).
#
# Stdout: one path per line — login file, `<home>/.bashrc`, `<zdotdir>/.zshenv`.
# shellcheck disable=SC2120  # called with no args at call site (SC2119 suppressed there)
shell__user_path_files() {
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  shell__user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zshenv"
  return 0
}

# @brief shell__write_env_block --opt <value> --profile-d <name> --marker <id> --content <c> [--scope system|user] [--home <dir>] — Resolve shell startup file targets and write an idempotent env-export block.
#
# Centralises the "auto vs. explicit file list" routing that every export-path
# handler needs: pick system-wide files when in system scope, user-scoped files
# when in user scope, or write directly to the caller-supplied list.
#
# Args:
#   --opt <value>          "auto" to target the standard system/user startup files, or
#                          a newline-separated list of absolute paths to target directly
#                          (pass via `$(printf '%s\n' "${ARRAY[@]}")`).
#   --profile-d <n>        Base filename for an /etc/profile.d/ drop-in; only used when
#                          --opt is "auto" and scope is system (optional).
#   --marker <id>          Block identifier passed to shell__sync_block.
#   --content <c>          Shell code to write inside the idempotency block.
#   --scope system|user    Explicit scope override. When omitted, falls back to
#                          users__is_root (system if root, user otherwise).
#   --home <dir>           Home directory for user-scoped writes; passed to
#                          shell__user_path_files (default: $HOME).
#
# When --opt is "auto":
#   system scope (--scope system, or root when --scope omitted) → shell__system_path_files
#   user scope   (--scope user,   or non-root when --scope omitted) → shell__user_path_files
# When --opt is an explicit newline-separated list: writes to those paths only.
shell__write_env_block() {
  local _opt="" _profile_d="" _marker="" _content="" _scope="" _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --opt)
        shift
        _opt="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        shift
        ;;
      --scope)
        shift
        _scope="$1"
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _target_files
  if [ "$_opt" = "auto" ]; then
    if [[ "$_scope" = "system" ]] || { [[ -z "$_scope" ]] && users__is_root; }; then
      logging__info "System-wide env block write (system scope)."
      _target_files="$(shell__system_path_files ${_profile_d:+--profile_d "$_profile_d"})"
    else
      logging__info "User-scoped env block write (user scope)."
      _target_files="$(shell__user_path_files --home "$_home")"
    fi
  else
    _target_files="$_opt"
  fi
  shell__sync_block --files "${_target_files}" --marker "${_marker}" --content "${_content}"
  return 0
}

# @brief shell__user_init_files [--home <dir>] [--zdotdir <dir>] — Print user startup file paths for a full initializer: bash login, `.bashrc`, `<zdotdir>/.zprofile`, `<zdotdir>/.zshrc`.
#
# Suitable for initializers that need to run in all contexts (e.g.
# `eval "$(brew shellenv)"`).
#
# Args:
#   --home <dir>    User home directory (default: `$HOME`).
#   --zdotdir <dir> ZDOTDIR override (default: auto-detected via `shell__detect_zdotdir`).
#
# Stdout: one path per line — login file, `<home>/.bashrc`, `<zdotdir>/.zprofile`, `<zdotdir>/.zshrc`.
shell__user_init_files() {
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  shell__user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zprofile"
  echo "${_zdotdir}/.zshrc"
  return 0
}

# @brief shell__user_rc_files [--home <dir>] [--zdotdir <dir>] — Print user-scoped interactive RC file paths (`.bashrc`, `<zdotdir>/.zshrc`). Excludes login files.
#
# Intended for initializers that must only run in interactive shells
# (e.g. conda init, shell prompt setup). Does NOT include login files —
# use `shell__user_init_files` when those are needed too.
#
# Args:
#   --home <dir>    User home directory (default: `$HOME`).
#   --zdotdir <dir> ZDOTDIR override (default: auto-detected via `shell__detect_zdotdir`).
#
# Stdout: one path per line — `<home>/.bashrc`, `<zdotdir>/.zshrc`.
shell__user_rc_files() {
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zshrc"
  return 0
}

# @brief shell__system_rc_files — Print system-wide interactive RC file paths (global bashrc, `<zshdir>/zshrc`). Does not include login or PATH-export files.
#
# Intended for system-wide interactive-only setup when no per-user targets
# are resolved (e.g. running as root with no resolved users).
#
# Stdout: global bashrc path, then `<zshdir>/zshrc`.
shell__system_rc_files() {
  shell__detect_bashrc
  echo "$(shell__detect_zshdir)/zshrc"
  return 0
}

# @brief shell__resolve_omz_theme --theme_slug <slug> --custom_dir <dir> — Given an `owner/repo` slug and `ZSH_CUSTOM` dir, print the `ZSH_THEME` value expected by oh-my-zsh.
#
# Falls back to the repo name alone if the `.zsh-theme` file cannot be found.
#
# Args:
#   --theme_slug <slug>  GitHub slug in "owner/repo" format.
#   --custom_dir <dir>   Path to $ZSH_CUSTOM (oh-my-zsh custom directory).
#
# Stdout: ZSH_THEME value (e.g. `repo-name/theme-stem` or just `repo-name`).
shell__resolve_omz_theme() {
  local slug="" custom_dir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --theme_slug)
        shift
        slug="$1"
        shift
        ;;
      --custom_dir)
        shift
        custom_dir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [ -z "$slug" ] && return 0

  local _repo_name
  _repo_name="$(basename "$slug")"
  local _theme_dir="${custom_dir}/themes/${_repo_name}"
  local _theme_file
  _theme_file="$(find "$_theme_dir" -maxdepth 1 -name '*.zsh-theme' 2> /dev/null | head -1)"

  if [ -n "$_theme_file" ]; then
    local _stem
    _stem="$(basename "${_theme_file%.zsh-theme}")"
    echo "${_repo_name}/${_stem}"
  else
    echo "$_repo_name"
  fi
  return 0
}

# @brief shell__ensure_bashenv — Detect or create the system-wide BASH_ENV file and register it in `/etc/environment`. Print the absolute path to the file.
#
# Callers are responsible for writing content to the returned path.
#
# Detection priority: `$BASH_ENV` (live env var) → `BASH_ENV=` in `/etc/environment` → create `<bashrc_dir>/bashenv`.
#
# Stdout: absolute path to the BASH_ENV file.
shell__ensure_bashenv() {
  # 1. Live environment variable
  if [ -n "${BASH_ENV:-}" ]; then
    logging__info "BASH_ENV already set to '${BASH_ENV}'; reusing."
    echo "$BASH_ENV"
    return 0
  fi
  # Allow tests (and callers) to override the path via _SHELL_ENV_FILE.
  local _env_file="${_SHELL_ENV_FILE:-/etc/environment}"
  # 2. Existing /etc/environment entry
  if [ -f "$_env_file" ]; then
    local _env_val
    _env_val="$(grep -m1 '^BASH_ENV=' "$_env_file" 2> /dev/null || true)"
    if [ -n "$_env_val" ]; then
      _env_val="${_env_val#BASH_ENV=}"
      _env_val="${_env_val#[\"\']}"
      _env_val="${_env_val%[\"\']}"
      logging__info "Found BASH_ENV='${_env_val}' in '${_env_file}'; reusing."
      echo "$_env_val"
      return 0
    fi
  fi
  # 3. Create new bashenv file and register in /etc/environment
  local _bashrc
  _bashrc="$(shell__detect_bashrc)"
  local _bashenv_dir
  _bashenv_dir="$(dirname "$_bashrc")"
  local _bashenv_path="${_bashenv_dir}/bashenv"
  logging__info "No BASH_ENV found; creating '${_bashenv_path}' and registering in '${_env_file}'."
  mkdir -p "$_bashenv_dir"
  [ -f "$_bashenv_path" ] || touch "$_bashenv_path"
  printf 'BASH_ENV="%s"\n' "$_bashenv_path" >> "$_env_file"
  echo "$_bashenv_path"
  return 0
}

# @brief shell__install_completion [--system] [--home <dir>] <shell> <name> <content> — Write a shell completion script to the appropriate completion directory.
#
# Selects the install path based on scope (system vs user) and shell:
#   bash    system: /etc/bash_completion.d/<name>
#           user:   <home>/.local/share/bash-completion/completions/<name>
#   zsh     system: <shell__detect_zshdir>/completions/_<name>
#           user:   <home>/.zfunc/_<name>
#   fish    system: /usr/share/fish/vendor_completions.d/<name>.fish
#           user:   <home>/.config/fish/completions/<name>.fish
#   nushell (no system path): <home>/.config/nushell/autoload/<name>.nu
#   elvish  (no system path): named block in <home>/.config/elvish/rc.elv
#
# Args:
#   --system      Use system-wide paths (root behaviour). When omitted, user paths are used.
#                 Ignored for nushell and elvish (no standard system paths exist).
#   --home <dir>  Home directory for user-scoped paths. Defaults to $HOME.
#   <shell>       Target shell: bash, zsh, fish, nushell, or elvish.
#   <name>        Completion file base name (tool name, e.g. "yq").
#   <content>     Completion script text to write.
#
# Returns: 0 on success, 1 for unsupported shells or write errors.
shell__install_completion() {
  local _system=false _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --system)
        _system=true
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) break ;;
    esac
  done
  local _shell="$1" _name="$2" _content="$3"
  local _dest
  case "${_shell}" in
    bash)
      if "${_system}"; then
        _dest="/etc/bash_completion.d/${_name}"
      else
        _dest="${_home}/.local/share/bash-completion/completions/${_name}"
      fi
      ;;
    zsh)
      if "${_system}"; then
        _dest="$(shell__detect_zshdir)/completions/_${_name}"
      else
        _dest="${_home}/.zfunc/_${_name}"
      fi
      ;;
    fish)
      if "${_system}"; then
        _dest="/usr/share/fish/vendor_completions.d/${_name}.fish"
      else
        _dest="${_home}/.config/fish/completions/${_name}.fish"
      fi
      ;;
    nushell)
      _dest="${_home}/.config/nushell/autoload/${_name}.nu"
      ;;
    elvish)
      local _rc="${_home}/.config/elvish/rc.elv"
      file__mkdir "$(dirname "${_rc}")"
      shell__write_block --file "${_rc}" --marker "${_name} completion" --content "${_content}"
      logging__success "Shell completion for '${_shell}' written to '${_rc}'."
      return 0
      ;;
    *)
      logging__error "unsupported shell '${_shell}' (expected: bash, zsh, fish, nushell, elvish)."
      return 1
      ;;
  esac
  file__mkdir "$(dirname "${_dest}")"
  printf '%s\n' "${_content}" | file__tee "${_dest}"
  logging__success "Shell completion for '${_shell}' written to '${_dest}'."
}

# @brief shell__create_symlink --src <s> --system-target <t> --user-target <t> — Create a symlink, choosing system-wide or user-scoped location based on write access.
#
# Places the symlink at <system-target> if the system target's parent directory
# exists and is writable by the caller; otherwise at <user-target>. If the
# chosen target equals src, no symlink is needed and the function returns
# without error.
#
# Errors if the chosen target path is a real file or directory (not a symlink).
# Creates parent directories of the target as needed.
#
# Args:
#   --src <s>            The path the symlink will point to.
#   --system-target <t>  Symlink path for system-wide installations.
#   --user-target <t>    Symlink path for user-scoped installations.
#
# Returns: 0 on success, 1 if the target is a real file or directory.
shell__create_symlink() {
  local _src="" _system_target="" _user_target=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --src)
        shift
        _src="$1"
        shift
        ;;
      --system-target)
        shift
        _system_target="$1"
        shift
        ;;
      --user-target)
        shift
        _user_target="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  # Choose symlink target based on write access to the target directory.
  # Walk up to the nearest existing ancestor of each target's parent to check
  # if the caller can write there (and thus create the full path via mkdir -p).
  # Prefer the system target; fall back to the user target; error if neither is
  # writable so the caller gets a clear diagnostic instead of a set -e death.
  # Exception: when --src lives under the user's home directory the installation
  # is inherently user-scoped, so skip the system target entirely and go
  # straight to the user target (even if the system dir happens to be writable).
  _nearest_writable_ancestor() {
    local _d
    _d="$(dirname "$1")"
    while [ ! -d "$_d" ]; do _d="$(dirname "$_d")"; done
    [ -w "$_d" ]
  }
  local _src_is_user_space=false
  if [[ -n "${HOME:-}" ]] && [[ "$_src" == "${HOME}/"* ]]; then
    _src_is_user_space=true
  fi
  local _target
  if ! $_src_is_user_space && _nearest_writable_ancestor "$_system_target"; then
    _target="$_system_target"
  elif _nearest_writable_ancestor "$_user_target"; then
    _target="$_user_target"
  else
    logging__error "Cannot create symlink: no writable location available (tried '${_system_target}' and '${_user_target}')."
    return 1
  fi
  unset -f _nearest_writable_ancestor
  # If src and target are the same path, no symlink is needed.
  if [[ "$_src" == "$_target" ]]; then
    logging__info "src and target are identical ('${_target}'); no symlink needed."
    return 0
  fi
  # Guard: refuse to clobber a real file or directory.
  if [[ -e "$_target" && ! -L "$_target" ]]; then
    logging__error "'${_target}' exists as a real file or directory; cannot create symlink."
    return 1
  fi
  # Remove stale symlink before recreating.
  [[ -L "$_target" ]] && rm -f "$_target"
  mkdir -p "$(dirname "$_target")"
  ln -s "$_src" "$_target"
  logging__success "Created symlink '${_target}' -> '${_src}'."
  return 0
}

# @brief shell__write_activation_snippets [--scope system|user] [--home <dir>] <marker> <profile_d_name> <snippet_func> [<shell>...] — Write activation snippets for each shell to the appropriate init files.
#
# Routes snippets based on scope (system vs user), shell, and the snippet
# function's exit code (0 = all contexts; 1 = interactive-only).
#
# Supported shells: bash, zsh, fish, tcsh, elvish.
#
# Shell notes:
#   fish   — no login/interactive distinction; system writes to /etc/fish/conf.d/,
#             user writes to ~/.config/fish/config.fish; _everywhere ignored.
#   tcsh   — system: /etc/csh.cshrc (+ /etc/csh.login when _everywhere=0);
#             user: ~/.tcshrc if it exists, else ~/.cshrc (+ ~/.login when _everywhere=0).
#   elvish — no system-wide config path; system scope iterates all resolved users and
#             writes to each user's ~/.config/elvish/rc.elv; _everywhere ignored.
#
# Args:
#   --scope system|user  Explicit scope override. When omitted, falls back to
#                        users__is_root (system if root, user otherwise).
#   --home <dir>         Home directory for user-scoped writes (default: $HOME).
#   <marker>             Idempotency marker passed to shell__sync_block.
#   <profile_d_name>     Basename for the /etc/profile.d/ file (system+bash+everywhere only).
#                        Also used (with .sh stripped and .fish appended) for /etc/fish/conf.d/.
#   <snippet_func>       Name of the function to call as `"$snippet_func" "$shell"`.
#                        stdout: snippet content; exit 0 = all contexts; exit 1 = interactive-only.
#   [<shell>...]         Shell names to iterate over (bash, zsh, fish, tcsh, elvish, ...).
shell__write_activation_snippets() {
  local _scope="" _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --scope)
        shift
        _scope="$1"
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      --)
        shift
        break
        ;;
      --*)
        shift
        shift
        ;;
      *) break ;;
    esac
  done
  local _marker="$1" _profile_d_name="$2" _snippet_func="$3"
  shift 3
  local _shell _snippet _everywhere _files
  local _is_system=false
  if [[ "$_scope" = "system" ]] || { [[ -z "$_scope" ]] && users__is_root; }; then
    _is_system=true
  fi
  if ! declare -f "$_snippet_func" > /dev/null; then
    logging__error "snippet function '${_snippet_func}' is not defined."
    return 1
  fi
  for _shell in "$@"; do
    [ -z "$_shell" ] && continue
    if _snippet="$("$_snippet_func" "$_shell")"; then
      _everywhere=0
    else
      _everywhere=$?
    fi
    [ -z "$_snippet" ] && continue
    if "$_is_system"; then
      if [ "$_everywhere" -eq 0 ]; then
        case "$_shell" in
          bash)
            local _benv
            _benv="$(shell__ensure_bashenv)"
            shell__sync_block --files "/etc/profile.d/$_profile_d_name"$'\n'"$_benv" \
              --marker "$_marker" --content "$_snippet"
            _files="$(shell__detect_bashrc)"
            ;;
          zsh) _files="$(shell__detect_zshdir)/zshenv" ;;
          fish) _files="/etc/fish/conf.d/${_profile_d_name%.sh}.fish" ;;
          tcsh)
            shell__sync_block --files "/etc/csh.login" --marker "$_marker" --content "$_snippet"
            _files="/etc/csh.cshrc"
            ;;
          elvish)
            local -a _elv_users=()
            mapfile -t _elv_users < <(users__resolve_list)
            local _eu
            for _eu in "${_elv_users[@]+"${_elv_users[@]}"}"; do
              local _euhome
              _euhome="$(users__resolve_home "$_eu" 2> /dev/null)" || continue
              [[ -z "$_euhome" ]] && continue
              local _eurc="${_euhome}/.config/elvish/rc.elv"
              file__mkdir "$(dirname "$_eurc")"
              [[ ! -f "$_eurc" ]] && printf '' | file__tee "$_eurc"
              shell__sync_block --files "$_eurc" --marker "$_marker" --content "$_snippet"
            done
            continue
            ;;
          *) continue ;;
        esac
      else
        case "$_shell" in
          bash) _files="$(shell__detect_bashrc)" ;;
          zsh) _files="$(shell__detect_zshdir)/zshrc" ;;
          fish) _files="/etc/fish/conf.d/${_profile_d_name%.sh}.fish" ;;
          tcsh) _files="/etc/csh.cshrc" ;;
          elvish)
            local -a _elv_users=()
            mapfile -t _elv_users < <(users__resolve_list)
            local _eu
            for _eu in "${_elv_users[@]+"${_elv_users[@]}"}"; do
              local _euhome
              _euhome="$(users__resolve_home "$_eu" 2> /dev/null)" || continue
              [[ -z "$_euhome" ]] && continue
              local _eurc="${_euhome}/.config/elvish/rc.elv"
              file__mkdir "$(dirname "$_eurc")"
              [[ ! -f "$_eurc" ]] && printf '' | file__tee "$_eurc"
              shell__sync_block --files "$_eurc" --marker "$_marker" --content "$_snippet"
            done
            continue
            ;;
          *) continue ;;
        esac
      fi
    else
      if [ "$_everywhere" -eq 0 ]; then
        case "$_shell" in
          bash)
            shell__sync_block --files "$(shell__user_login_file --home "$_home")" \
              --marker "$_marker" --content "$_snippet"
            _files="${_home}/.bashrc"
            ;;
          zsh) _files="$(shell__detect_zdotdir --home "$_home")/.zshenv" ;;
          fish) _files="${_home}/.config/fish/config.fish" ;;
          tcsh)
            local _tcsh_rc="${_home}/.cshrc"
            [[ -f "${_home}/.tcshrc" ]] && _tcsh_rc="${_home}/.tcshrc"
            shell__sync_block --files "${_home}/.login" --marker "$_marker" --content "$_snippet"
            _files="$_tcsh_rc"
            ;;
          elvish) _files="${_home}/.config/elvish/rc.elv" ;;
          *) continue ;;
        esac
      else
        case "$_shell" in
          bash) _files="${_home}/.bashrc" ;;
          zsh) _files="$(shell__detect_zdotdir --home "$_home")/.zshrc" ;;
          fish) _files="${_home}/.config/fish/config.fish" ;;
          tcsh)
            local _tcsh_rc="${_home}/.cshrc"
            [[ -f "${_home}/.tcshrc" ]] && _tcsh_rc="${_home}/.tcshrc"
            _files="$_tcsh_rc"
            ;;
          elvish) _files="${_home}/.config/elvish/rc.elv" ;;
          *) continue ;;
        esac
      fi
    fi
    file__mkdir "$(dirname "$_files")"
    if [[ ! -f "$_files" ]]; then
      printf '' | file__tee "$_files"
    fi
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_snippet"
  done
}

# @brief shell__prefix_link_bins — Create symlinks for a set of prefix bins into target directories.
#
# Args:
#   --bin-dir <dir>   Source directory containing the binaries.
#   --bins <names>    Space-separated binary names.
#   --target <dir>    Target directory (may be repeated).
shell__prefix_link_bins() {
  local _bin_dir="" _bins=""
  local -a _targets=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --target)
        shift
        _targets+=("$1")
        shift
        ;;
      *) shift ;;
    esac
  done
  local _bin_name _target
  for _bin_name in ${_bins}; do
    [[ -f "${_bin_dir}/${_bin_name}" ]] || continue
    for _target in "${_targets[@]}"; do
      shell__create_symlink \
        --src "${_bin_dir}/${_bin_name}" \
        --system-target "${_target}/${_bin_name}" \
        --user-target "${_target}/${_bin_name}"
    done
  done
}

# @brief shell__prefix_unlink_bins — Remove symlinks for a set of prefix bins from target directories.
#
# Args:
#   --bin-dir <dir>   Source directory (only used as context; not accessed).
#   --bins <names>    Space-separated binary names.
#   --target <dir>    Target directory to remove symlinks from (may be repeated).
shell__prefix_unlink_bins() {
  local _bins=""
  local -a _targets=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --bin-dir)
        shift
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --target)
        shift
        _targets+=("$1")
        shift
        ;;
      *) shift ;;
    esac
  done
  local _bin_name _target
  for _bin_name in ${_bins}; do
    for _target in "${_targets[@]}"; do
      local _link="${_target}/${_bin_name}"
      [ -L "${_link}" ] || continue
      file__rm "${_link}"
      logging__remove "Removed symlink '${_link}'."
    done
  done
}

# @brief shell__run_prefix_undiscovery — Remove prefix-discovery artifacts: downstream symlinks and PATH export blocks.
#
# Accepts the same arguments as shell__run_prefix_discovery. Always attempts removal of
# both symlinks (from resolved target dirs) and PATH export block (from appropriate shell
# files), regardless of the discovery mode. Each removal operation is a no-op when the
# artifact does not exist (shell__sync_block skips missing markers; shell__prefix_unlink_bins
# uses a [ -L ] guard).
#
# Args: same as shell__run_prefix_discovery (--cmd-var and --discovery are accepted but ignored).
shell__run_prefix_undiscovery() {
  local _disc_prefix="" _bin_dir="bin"
  local _bins="" _symlinks_ref="" _exports_ref="" _marker="" _profile_d=""
  local _symlink_root="/usr/local/bin" _symlink_nonroot="${HOME}/.local/bin"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --prefix)
        shift
        _disc_prefix="$1"
        shift
        ;;
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --symlinks-ref)
        shift
        _symlinks_ref="$1"
        shift
        ;;
      --exports-ref)
        shift
        _exports_ref="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --symlink-root)
        shift
        _symlink_root="$1"
        shift
        ;;
      --symlink-nonroot)
        shift
        _symlink_nonroot="$1"
        shift
        ;;
      *)
        shift
        [ $# -gt 0 ] && shift || true
        ;;
    esac
  done
  local _pfx_bin_dir="${_disc_prefix}/${_bin_dir}"

  # Determine scope from prefix path.
  local _disc_scope _disc_home
  if ! users__is_user_path "${_disc_prefix}"; then
    _disc_scope="system"
    _disc_home=""
  else
    _disc_scope="user"
    _disc_home="$(users__home_of_path_owner "${_disc_prefix}")"
  fi

  # Resolve symlink targets.
  local -a _sl_targets=()
  if [[ -n "$_symlinks_ref" ]]; then
    local -n _rpud_sl="${_symlinks_ref}"
    [[ "${#_rpud_sl[@]}" -gt 0 ]] && _sl_targets=("${_rpud_sl[@]}")
  fi
  if [[ "${#_sl_targets[@]}" -eq 0 ]]; then
    if [[ "$_disc_scope" = "system" ]]; then
      _sl_targets=("${_symlink_root}")
    else
      _sl_targets=("${_symlink_nonroot}")
    fi
  fi

  # Remove downstream symlinks from all resolved targets.
  local _sl_dir
  local -a _sl_args=()
  for _sl_dir in "${_sl_targets[@]}"; do _sl_args+=(--target "${_sl_dir}"); done
  shell__prefix_unlink_bins --bin-dir "${_pfx_bin_dir}" --bins "${_bins}" "${_sl_args[@]}"

  # Remove PATH export block from all appropriate shell files.
  [[ -n "${_marker}" ]] || return 0
  local _export_files
  if [[ -n "$_exports_ref" ]]; then
    local -n _rpud_ex="${_exports_ref}"
    if [[ "${#_rpud_ex[@]}" -gt 0 ]]; then
      _export_files="$(printf '%s\n' "${_rpud_ex[@]}")"
      shell__sync_block --files "${_export_files}" --marker "${_marker}"
      return 0
    fi
  fi
  if [[ "$_disc_scope" = "system" ]]; then
    _export_files="$(shell__system_path_files ${_profile_d:+--profile_d "${_profile_d}"})"
  else
    _export_files="$(shell__user_path_files ${_disc_home:+--home "${_disc_home}"})"
  fi
  shell__sync_block --files "${_export_files}" --marker "${_marker}"
}

# @brief shell__remove_activation_snippets — Remove activation blocks from all applicable shell init files.
#
# Mirror of shell__write_activation_snippets. Because the original snippet function is not
# available at removal time, this function attempts removal from ALL possible file locations
# for each shell (both "everywhere" paths and "rc-only" paths). shell__sync_block skips files
# that don't contain the marker, so over-broad removal is safe.
#
# Supported shells: bash, zsh, fish, tcsh, elvish.
# See shell__write_activation_snippets for per-shell path details.
# tcsh removal tries both ~/.tcshrc and ~/.cshrc since write-time selection is not known.
# elvish system scope iterates all resolved users (no system-wide config path exists).
#
# Args:
#   --scope system|user   Scope (default: system when root, user otherwise).
#   --home <dir>          Home directory for user-scoped removal.
#   <marker>              Idempotency marker (positional, after options).
#   <profile_d_name>      /etc/profile.d basename (positional).
#   [<shell>...]          Shells to process (positional, remaining).
shell__remove_activation_snippets() {
  local _scope="" _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --scope)
        shift
        _scope="$1"
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      --)
        shift
        break
        ;;
      --*)
        shift
        [ $# -gt 0 ] && shift || true
        ;;
      *) break ;;
    esac
  done
  local _marker="$1" _profile_d_name="$2"
  shift 2
  local _shell _is_system=false
  if [[ "$_scope" = "system" ]] || { [[ -z "$_scope" ]] && users__is_root; }; then
    _is_system=true
  fi
  for _shell in "$@"; do
    [ -z "$_shell" ] && continue
    local -a _files_list=()
    if "${_is_system}"; then
      case "$_shell" in
        bash)
          _files_list+=("/etc/profile.d/$_profile_d_name")
          local _benv
          _benv="$(shell__ensure_bashenv 2> /dev/null || true)"
          [ -n "$_benv" ] && _files_list+=("$_benv")
          _files_list+=("$(shell__detect_bashrc)")
          ;;
        zsh)
          _files_list+=("$(shell__detect_zshdir)/zshenv")
          _files_list+=("$(shell__detect_zshdir)/zshrc")
          ;;
        fish) _files_list+=("/etc/fish/conf.d/${_profile_d_name%.sh}.fish") ;;
        tcsh) _files_list+=("/etc/csh.login" "/etc/csh.cshrc") ;;
        elvish)
          local -a _elv_users=()
          mapfile -t _elv_users < <(users__resolve_list)
          local _eu
          for _eu in "${_elv_users[@]+"${_elv_users[@]}"}"; do
            local _euhome
            _euhome="$(users__resolve_home "$_eu" 2> /dev/null)" || continue
            [[ -z "$_euhome" ]] && continue
            shell__sync_block --files "${_euhome}/.config/elvish/rc.elv" --marker "$_marker"
          done
          continue
          ;;
        *) continue ;;
      esac
    else
      case "$_shell" in
        bash)
          _files_list+=("$(shell__user_login_file --home "$_home")")
          _files_list+=("${_home}/.bashrc")
          ;;
        zsh)
          local _zdotdir
          _zdotdir="$(shell__detect_zdotdir --home "$_home")"
          _files_list+=("${_zdotdir}/.zshenv")
          _files_list+=("${_zdotdir}/.zshrc")
          ;;
        fish) _files_list+=("${_home}/.config/fish/config.fish") ;;
        tcsh) _files_list+=("${_home}/.login" "${_home}/.cshrc" "${_home}/.tcshrc") ;;
        elvish) _files_list+=("${_home}/.config/elvish/rc.elv") ;;
        *) continue ;;
      esac
    fi
    local _f
    for _f in "${_files_list[@]}"; do
      [ -n "$_f" ] && shell__sync_block --files "$_f" --marker "$_marker"
    done
  done
}

# @brief shell__prefix_export_path — Write a PATH-prepend export block for a prefix bin directory.
#
# Args:
#   --bin-dir <dir>      Directory to prepend to PATH.
#   --exports-ref <var>  Name of array variable with explicit export file paths (optional).
#   --marker <id>        Idempotency marker.
#   --profile-d <name>   /etc/profile.d basename for the system-wide drop-in.
#   --scope system|user  Passed through to shell__write_env_block (optional).
#   --home <dir>         Home directory for user-scoped writes (default: $HOME).
shell__prefix_export_path() {
  local _bin_dir="" _exports_ref="" _marker="" _profile_d="" _scope="" _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --exports-ref)
        shift
        _exports_ref="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --scope)
        shift
        _scope="$1"
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _export_opt
  if [[ -n "$_exports_ref" ]]; then
    local -n _pep_ex="${_exports_ref}"
    if [[ "${#_pep_ex[@]}" -eq 0 ]]; then
      _export_opt="auto"
    else
      _export_opt="$(printf '%s\n' "${_pep_ex[@]}")"
    fi
  else
    _export_opt="auto"
  fi
  local _content
  # shellcheck disable=SC2162
  IFS= read -r -d '' _content << 'EOBLOCK' || true
_shell__df_prepend_path() {
  local _d="$1" _p="${PATH:-}" _r="" _e
  while [ -n "$_p" ]; do
    _e="${_p%%:*}"; [ "$_p" = "${_p#*:}" ] && _p="" || _p="${_p#*:}"
    [ "$_e" = "$_d" ] || _r="${_r:+${_r}:}${_e}"
  done
  export PATH="${_d}${_r:+:${_r}}"
}
EOBLOCK
  _content="${_content}_shell__df_prepend_path \"${_bin_dir}\"
unset -f _shell__df_prepend_path"
  shell__write_env_block \
    --opt "${_export_opt}" \
    --profile-d "${_profile_d}" \
    --marker "${_marker}" \
    --content "${_content}" \
    ${_scope:+--scope "${_scope}"} \
    --home "${_home}"
}

# @brief shell__run_prefix_discovery — Decide how to make prefix bins discoverable and record the expected verification command.
#
# Resolves symlink targets, applies the discovery decision (none|symlink|shell|all|auto),
# delegates execution to shell__prefix_link_bins / shell__prefix_export_path, then stores
# the expected verification command in the variable named by --cmd-var via printf -v.
#
# Args:
#   --prefix <path>       Installation prefix.
#   --bin-dir <subdir>    Subdirectory for binaries (default: bin).
#   --discovery <value>   none|symlink|shell|all|auto (default: auto).
#   --runtime-path <val>  Colon-separated PATH for the "already on PATH" and cmd checks.
#   --bins <names>        Space-separated binary names to symlink.
#   --symlinks-ref <var>  Name of array variable with explicit symlink target dirs.
#   --exports-ref <var>   Name of array variable with explicit export file paths.
#   --marker <id>         Idempotency marker for the PATH export block.
#   --profile-d <name>    /etc/profile.d basename for the PATH export drop-in (root only).
#   --bin <name>          Primary binary name for --cmd-var output.
#   --cmd-var <varname>   Name of variable to set with the expected command string.
#   --symlink-root <dir>  Fallback symlink target for root installs (default: /usr/local/bin).
#   --symlink-nonroot <dir> Fallback symlink target for non-root installs (default: ${HOME}/.local/bin).
#   --no-symlinks         Disable symlink creation.
#   --no-exports          Disable PATH export writing.
shell__run_prefix_discovery() {
  local _disc_prefix="" _bin_dir="bin" _discovery="auto" _runtime_path="${PATH:-}"
  local _bins="" _symlinks_ref="" _exports_ref="" _marker="" _profile_d=""
  local _bin="" _cmd_var="" _no_symlinks=false _no_exports=false
  local _symlink_root="/usr/local/bin" _symlink_nonroot="${HOME}/.local/bin"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --prefix)
        shift
        _disc_prefix="$1"
        shift
        ;;
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --discovery)
        shift
        _discovery="${1:-auto}"
        shift
        ;;
      --runtime-path)
        shift
        _runtime_path="$1"
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --symlinks-ref)
        shift
        _symlinks_ref="$1"
        shift
        ;;
      --exports-ref)
        shift
        _exports_ref="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --bin)
        shift
        _bin="$1"
        shift
        ;;
      --cmd-var)
        shift
        _cmd_var="$1"
        shift
        ;;
      --symlink-root)
        shift
        _symlink_root="$1"
        shift
        ;;
      --symlink-nonroot)
        shift
        _symlink_nonroot="$1"
        shift
        ;;
      --no-symlinks)
        _no_symlinks=true
        shift
        ;;
      --no-exports)
        _no_exports=true
        shift
        ;;
      *) shift ;;
    esac
  done
  local _pfx_bin_dir="${_disc_prefix}/${_bin_dir}"

  # Determine system vs. user scope from the prefix path rather than the caller's UID.
  local _disc_scope _disc_home
  if ! users__is_user_path "${_disc_prefix}"; then
    _disc_scope="system"
    _disc_home=""
  else
    _disc_scope="user"
    _disc_home="$(users__home_of_path_owner "${_disc_prefix}")"
  fi

  # Resolve symlink targets.
  local -a _sl_targets=()
  if [[ "$_no_symlinks" != true ]]; then
    if [[ -n "$_symlinks_ref" ]]; then
      local -n _rpd_sl="${_symlinks_ref}"
      [[ "${#_rpd_sl[@]}" -gt 0 ]] && _sl_targets=("${_rpd_sl[@]}")
    fi
    if [[ "${#_sl_targets[@]}" -eq 0 ]]; then
      if [[ "$_disc_scope" = "system" ]]; then
        _sl_targets=("${_symlink_root}")
      else
        _sl_targets=("${_symlink_nonroot}")
      fi
    fi
  fi

  # Discovery decision.
  local _call_symlinks=false _call_exports=false
  case "${_discovery}" in
    none) ;;
    symlink) [[ "$_no_symlinks" != true ]] && _call_symlinks=true ;;
    shell) [[ "$_no_exports" != true ]] && _call_exports=true ;;
    all)
      [[ "$_no_symlinks" != true ]] && _call_symlinks=true
      [[ "$_no_exports" != true ]] && _call_exports=true
      ;;
    auto)
      case ":${_runtime_path}:" in
        *":${_pfx_bin_dir}:"*) ;;
        *)
          if [[ "$_no_symlinks" != true ]]; then
            local _has_real=false _t
            for _t in "${_sl_targets[@]}"; do
              [[ "$_t" != "$_pfx_bin_dir" ]] && {
                _has_real=true
                break
              }
            done
            if "${_has_real}"; then
              _call_symlinks=true
            elif [[ "$_no_exports" != true ]]; then
              # Symlinks not viable (all targets equal prefix/bin) — fall back to PATH export.
              _call_exports=true
            fi
          elif [[ "$_no_exports" != true ]]; then
            # Symlinks suppressed via --no-symlinks — fall back to PATH export.
            _call_exports=true
          fi
          ;;
      esac
      ;;
  esac

  # Execute.
  if "${_call_symlinks}"; then
    local _sl_dir _sl_args=()
    for _sl_dir in "${_sl_targets[@]}"; do _sl_args+=(--target "${_sl_dir}"); done
    shell__prefix_link_bins --bin-dir "${_pfx_bin_dir}" --bins "${_bins}" "${_sl_args[@]}"
  fi
  if "${_call_exports}"; then
    shell__prefix_export_path \
      --bin-dir "${_pfx_bin_dir}" \
      --exports-ref "${_exports_ref}" \
      --marker "${_marker}" \
      --profile-d "${_profile_d}" \
      --scope "${_disc_scope}" \
      ${_disc_home:+--home "${_disc_home}"}
  fi

  # Set expected verification command.
  if [[ -n "$_cmd_var" && -n "$_bin" ]]; then
    local _expected_cmd
    case ":${_runtime_path}:" in
      *":${_pfx_bin_dir}:"*)
        _expected_cmd="${_bin}"
        ;;
      *)
        if "${_call_symlinks}" && [[ "${#_sl_targets[@]}" -gt 0 ]]; then
          local _sl_first="${_sl_targets[0]}"
          case ":${_runtime_path}:" in
            *":${_sl_first}:"*) _expected_cmd="${_bin}" ;;
            *) _expected_cmd="${_sl_first}/${_bin}" ;;
          esac
        elif "${_call_exports}"; then
          if [[ "$_disc_scope" = "system" ]]; then
            _expected_cmd="${_bin}"
          else
            _expected_cmd="${_pfx_bin_dir}/${_bin}"
          fi
        else
          _expected_cmd="${_pfx_bin_dir}/${_bin}"
        fi
        ;;
    esac
    printf -v "${_cmd_var}" '%s' "${_expected_cmd}"
  fi
}
