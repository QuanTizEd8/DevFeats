# shellcheck shell=bash
# File and archive helpers: extract `.tar.xz`, `.tar.gz`, `.tgz`, and `.zip` archives.
#
# Returns 1 on unrecognized format or missing extraction tool.

read -r -d '' _FILE__XZ_MANIFEST << 'EOF' || true
packages:
  - name: xz
    apt: xz-utils
EOF

read -r -d '' _FILE__COREUTILS_MANIFEST << 'EOF' || true
packages:
  - when: {pm: [apt, apk, dnf, yum, zypper, pacman]}
    packages: [coreutils]
EOF

# _file__ensure_tool <cmd> <pkg> [context] (internal) — Ensure <cmd> is on PATH; install <pkg> via ospkg if absent.
# [context] is an optional phrase inserted as "is required <context> but could not be installed".
_file__ensure_tool() {
  command -v "$1" > /dev/null 2>&1 && return 0
  ospkg__install_tracked "lib-file" "$2" || true
  command -v "$1" > /dev/null 2>&1 && return 0
  logging__error "file.sh: $1 is required${3:+ $3} but could not be installed."
  return 1
}

# _file__ensure_extract_tool <ext> (internal)
# Ensures the extraction tool for <ext> is available; installs it via ospkg when possible.
# <ext>: "zip" (installs unzip), "xz" (installs xz-utils/xz), "bz2" (installs bzip2), "gz" (installs gzip), "tar" (installs tar).
_file__ensure_extract_tool() {
  local _ext="$1"
  case "$_ext" in
    zip) _file__ensure_tool unzip unzip "to extract .zip archives" ;;
    xz)
      command -v xz > /dev/null 2>&1 && return 0
      ospkg__run --manifest "$_FILE__XZ_MANIFEST" --build-group "lib-file" --skip_installed || true
      command -v xz > /dev/null 2>&1 && return 0
      logging__error "file.sh: xz is required to extract .tar.xz archives but could not be installed."
      return 1
      ;;
    bz2) _file__ensure_tool bzip2 bzip2 "to extract .tar.bz2 archives" ;;
    gz) _file__ensure_tool gzip gzip "to extract .tar.gz archives" ;;
    tar) _file__ensure_tool tar tar "" ;;
    *) return 0 ;;
  esac
}

# _file__ensure_install_cmd (internal) — Ensure `install` (coreutils) is available.
# `install` is provided by GNU coreutils on Linux (including BusyBox on Alpine)
# and by BSD utils on macOS. It is absent only in severely stripped container
# images. Falls back to ospkg when missing.
_file__ensure_install_cmd() {
  command -v install > /dev/null 2>&1 && return 0
  logging__info "file.sh: 'install' command not found; installing coreutils."
  ospkg__run --manifest "$_FILE__COREUTILS_MANIFEST" --build-group "lib-file" --skip_installed || true
  if ! command -v install > /dev/null 2>&1; then
    logging__error "file.sh: 'install' is required but could not be installed."
    return 1
  fi
  return 0
}

# @brief file__append_privileged <file> — Append stdin to <file>, escalating privilege only if needed.
#
# If <file> is writable by the current process (or does not yet exist but its
# parent directory is writable), appends directly. Otherwise delegates to
# `users__run_privileged` so the append runs as root. Writability is checked
# before reading stdin so the stream is never consumed before the path is chosen.
#
# Args:
#   <file>  Absolute path to the file to append to.
#
# Returns: 0 on success, non-zero on failure.
file__append_privileged() {
  local _file="$1"
  if [ -w "$_file" ] || { [ ! -e "$_file" ] && [ -w "$(dirname "$_file")" ]; }; then
    cat >> "$_file"
  else
    # shellcheck disable=SC2016
    users__run_privileged sh -c 'cat >> "$1"' _ "$_file"
  fi
}

# @brief file__install_dir [--owner <user>] [--group <group>] [--mode <mode>] <dir>... — Create one or more directories with specified ownership and permissions.
#
# Uses `install -d` (GNU coreutils on Linux, BSD utils on macOS — identical
# flags on both). Sets ownership and mode both on creation and on pre-existing
# directories. Installs coreutils via ospkg if `install` is not available.
#
# Args:
#   --owner <user>  Owner username. Optional.
#   --group <group> Group name. Optional.
#   --mode <mode>   Permissions in octal (default: 0755).
#   <dir>...        One or more directory paths to create.
#
# Returns: 0 on success, 1 if `install` is unavailable or the operation fails.
file__install_dir() {
  local _owner="" _group="" _mode="0755"
  local -a _dirs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner)
        _owner="$2"
        shift 2
        ;;
      --group)
        _group="$2"
        shift 2
        ;;
      --mode)
        _mode="$2"
        shift 2
        ;;
      *)
        _dirs+=("$1")
        shift
        ;;
    esac
  done
  if [[ ${#_dirs[@]} -eq 0 ]]; then
    logging__error "file__install_dir: no directories specified"
    return 1
  fi
  _file__ensure_install_cmd || return 1
  local -a _cmd=(install -d -m "$_mode")
  [[ -n "$_owner" ]] && _cmd+=(-o "$_owner")
  [[ -n "$_group" ]] && _cmd+=(-g "$_group")
  # Escalate when setting ownership to another user, or when any target dir
  # (or its nearest existing ancestor) is not writable by the current process.
  local _needs_priv=false
  if [[ -n "$_owner" && "$_owner" != "$(id -un)" ]]; then
    _needs_priv=true
  else
    local _d _existing
    for _d in "${_dirs[@]}"; do
      _existing="$(file__nearest_existing "$_d")"
      [[ ! -w "$_existing" ]] && {
        _needs_priv=true
        break
      }
    done
  fi
  if $_needs_priv; then
    users__run_privileged "${_cmd[@]}" "${_dirs[@]}"
  else
    "${_cmd[@]}" "${_dirs[@]}"
  fi
}

# @brief file__mkdir <dir>... — Create directories (mkdir -p), escalating privilege only if needed.
#
# Uses `mkdir -p` for each path. Escalates to `users__run_privileged` if the
# nearest existing ancestor of any target directory is not writable by the
# current process.
#
# Args:
#   <dir>...  One or more directory paths to create.
#
# Returns: 0 on success, non-zero on failure.
file__mkdir() {
  local _needs_priv=false _d
  for _d in "$@"; do
    [[ ! -w "$(file__nearest_existing "$_d")" ]] && {
      _needs_priv=true
      break
    }
  done
  if $_needs_priv; then
    users__run_privileged mkdir -p "$@"
  else
    mkdir -p "$@"
  fi
}

# @brief file__cp <arg>... — Copy files or directories (cp), escalating privilege only if needed.
#
# Forwards all arguments to `cp`. The destination is the last argument.
# Escalates to `users__run_privileged` if the destination (or its nearest
# existing ancestor) is not writable by the current process.
#
# Args:
#   <arg>...  Any combination of `cp` flags, source paths, and destination (last arg).
#
# Returns: 0 on success, non-zero on failure.
file__cp() {
  local _dest="${!#}"
  local _needs_priv=false
  if [[ -e "$_dest" && ! -w "$_dest" ]]; then
    _needs_priv=true
  elif [[ ! -e "$_dest" && ! -w "$(file__nearest_existing "$(dirname "$_dest")")" ]]; then
    _needs_priv=true
  fi
  if $_needs_priv; then
    users__run_privileged cp "$@"
  else
    cp "$@"
  fi
}

# @brief file__chmod [flags] <mode> <path>... — chmod, escalating privilege only if needed.
#
# Parses leading flags (e.g. `-R`), then the mode, then one or more paths.
# Escalates to `users__run_privileged` if any path (or its nearest existing
# ancestor) is not writable by the current process.
#
# Args:
#   [flags]   Optional chmod flags (e.g. -R). Must appear before <mode>.
#   <mode>    Permission mode (e.g. 644, +x, g+rw).
#   <path>... One or more target paths.
#
# Returns: 0 on success, non-zero on failure.
file__chmod() {
  local -a _flags=() _paths=()
  local _mode=""
  while [[ $# -gt 0 ]]; do
    if [[ -z "$_mode" && "$1" == -* ]]; then
      _flags+=("$1")
      shift
    elif [[ -z "$_mode" ]]; then
      _mode="$1"
      shift
    else
      _paths+=("$1")
      shift
    fi
  done
  local _needs_priv=false _p
  for _p in "${_paths[@]}"; do
    if [[ -e "$_p" && ! -w "$_p" ]]; then
      _needs_priv=true
      break
    elif [[ ! -e "$_p" && ! -w "$(file__nearest_existing "$_p")" ]]; then
      _needs_priv=true
      break
    fi
  done
  if $_needs_priv; then
    users__run_privileged chmod "${_flags[@]+"${_flags[@]}"}" "$_mode" "${_paths[@]}"
  else
    chmod "${_flags[@]+"${_flags[@]}"}" "$_mode" "${_paths[@]}"
  fi
}

# @brief file__chown [flags] <spec> <path>... — chown, escalating privilege only if needed.
#
# Parses leading flags (e.g. `-R`), then the owner spec, then one or more
# paths. Escalates to `users__run_privileged` if the spec references a
# different user than the current one, or if any path (or its nearest existing
# ancestor) is not writable by the current process.
#
# Args:
#   [flags]   Optional chown flags (e.g. -R). Must appear before <spec>.
#   <spec>    Owner spec (e.g. user, user:group).
#   <path>... One or more target paths.
#
# Returns: 0 on success, non-zero on failure.
file__chown() {
  local -a _flags=() _paths=()
  local _spec=""
  while [[ $# -gt 0 ]]; do
    if [[ -z "$_spec" && "$1" == -* ]]; then
      _flags+=("$1")
      shift
    elif [[ -z "$_spec" ]]; then
      _spec="$1"
      shift
    else
      _paths+=("$1")
      shift
    fi
  done
  # Privilege is needed when the spec names a different user, or when any
  # target path is not writable by the current process.
  local _spec_user="${_spec%%:*}"
  local _needs_priv=false _p
  if [[ -n "$_spec_user" && "$_spec_user" != "$(id -un)" ]]; then
    _needs_priv=true
  else
    for _p in "${_paths[@]}"; do
      if [[ -e "$_p" && ! -w "$_p" ]]; then
        _needs_priv=true
        break
      elif [[ ! -e "$_p" && ! -w "$(file__nearest_existing "$_p")" ]]; then
        _needs_priv=true
        break
      fi
    done
  fi
  if $_needs_priv; then
    users__run_privileged chown "${_flags[@]+"${_flags[@]}"}" "$_spec" "${_paths[@]}"
  else
    chown "${_flags[@]+"${_flags[@]}"}" "$_spec" "${_paths[@]}"
  fi
}

# @brief file__tee [--append] <file> — Write stdin to <file>, escalating privilege only if needed.
#
# If <file> is writable by the current process (or does not yet exist but its
# parent directory is writable), writes directly via `cat`. Otherwise delegates
# to `users__run_privileged`. stdout is always suppressed.
#
# Args:
#   --append  Append to <file> rather than overwrite. Alias: -a.
#   <file>    Destination path.
#
# Returns: 0 on success, non-zero on failure.
file__tee() {
  local _append=false _file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --append | -a)
        _append=true
        shift
        ;;
      *)
        _file="$1"
        shift
        ;;
    esac
  done
  if [[ -z "$_file" ]]; then
    logging__error "file__tee: no file specified"
    return 1
  fi
  local _needs_priv=false
  if [[ -f "$_file" && ! -w "$_file" ]]; then
    _needs_priv=true
  elif [[ ! -f "$_file" && ! -w "$(file__nearest_existing "$(dirname "$_file")")" ]]; then
    _needs_priv=true
  fi
  if $_needs_priv; then
    if $_append; then
      # shellcheck disable=SC2016
      users__run_privileged sh -c 'cat >> "$1"' _ "$_file"
    else
      # shellcheck disable=SC2016
      users__run_privileged sh -c 'cat > "$1"' _ "$_file"
    fi
  else
    if $_append; then
      cat >> "$_file"
    else
      cat > "$_file"
    fi
  fi
}

# @brief file__detect_type <file> — Detect file type from magic bytes.
#
# Reads the first 6 bytes of <file> to identify its format, independent of
# filename or extension.
#
# Stdout: one of: gzip | xz | bzip2 | zip | elf | macho | script | unknown
# Returns: 0 always (unknown is a valid result, not an error).
file__detect_type() {
  local _file="$1" _hex
  _hex="$(od -An -tx1 -N 6 "$_file" 2> /dev/null | tr -d ' \n')"
  case "${_hex}" in
    1f8b*) printf 'gzip' ;;
    fd377a585a00*) printf 'xz' ;;
    425a68*) printf 'bzip2' ;;
    504b0304*) printf 'zip' ;;
    7f454c46*) printf 'elf' ;;
    cafebabe* | cefaedfe* | cffaedfe*) printf 'macho' ;;
    2321*) printf 'script' ;;
    *) printf 'unknown' ;;
  esac
}

# @brief file__extract_archive <archive_file> <dest_dir> [<original_name>] [--strip N] — Extract a `.tar.xz`, `.tar.gz`, `.tgz`, `.tar.bz2`, or `.zip` archive to `<dest_dir>`.
#
# `<original_name>` is used for format detection when `<archive_file>` is a temp
# path with no meaningful extension (e.g. a mktemp output). When omitted,
# the basename of `<archive_file>` is used.
#
# Args:
#   <archive_file>   Path to the archive to extract.
#   <dest_dir>       Destination directory (created if absent).
#   <original_name>  Optional filename used for extension-based format detection.
#   --strip N        Strip N leading path components (tar --strip-components=N). Ignored for zip.
#
# Returns: 0 on success, 1 on unrecognized format or missing extraction tool.
file__extract_archive() {
  local _arc="$1" _dest="$2"
  local _name _strip=""
  if [ "${3:-}" = "--strip" ]; then
    _name="$(basename "$_arc")"
    _strip="${4:-}"
  elif [ "${4:-}" = "--strip" ]; then
    _name="${3:-$(basename "$_arc")}"
    _strip="${5:-}"
  else
    _name="${3:-$(basename "$_arc")}"
  fi
  local -a _strip_arg=()
  [ -n "$_strip" ] && _strip_arg=(--strip-components="$_strip")
  mkdir -p "$_dest"
  case "$_name" in
    *.tar.xz)
      _file__ensure_extract_tool tar || return 1
      _file__ensure_extract_tool xz || return 1
      tar -xJf "$_arc" -C "$_dest" "${_strip_arg[@]}"
      ;;
    *.tar.gz | *.tgz)
      _file__ensure_extract_tool tar || return 1
      _file__ensure_extract_tool gz || return 1
      tar -xzf "$_arc" -C "$_dest" "${_strip_arg[@]}"
      ;;
    *.tar.bz2)
      _file__ensure_extract_tool tar || return 1
      _file__ensure_extract_tool bz2 || return 1
      tar -xjf "$_arc" -C "$_dest" "${_strip_arg[@]}"
      ;;
    *.zip)
      _file__ensure_extract_tool zip || return 1
      unzip -q -o "$_arc" -d "$_dest"
      ;;
    *)
      logging__warn "Unrecognized archive format: '$(basename "$_name")'. Skipping."
      return 1
      ;;
  esac
}

# @brief file__nearest_existing <path> — Walk up dirname until an existing path component is found.
#
# Useful for resolving ownership or write permission of a path that may not yet
# exist by examining the nearest ancestor that does.
#
# Args:
#   <path>  Absolute path to examine (need not exist).
#
# Stdout: nearest existing ancestor path (or `/` when nothing above root exists).
file__nearest_existing() {
  local _p="$1"
  while [[ "$_p" != "/" && ! -e "$_p" ]]; do _p="$(dirname "$_p")"; done
  printf '%s\n' "$_p"
}

# @brief file__tmpdir [<name>] — Return (and create if needed) a named subdirectory of the process-lifetime temp directory `_LOGGING__SYSSET_TMPDIR`. Idempotent.
#
# Safe to call from library code that does not control the script entry
# point, even if `logging__setup` has not yet been called. `_LOGGING__SYSSET_TMPDIR`
# is lazy-initialised on first call. The entire tree is deleted by
# `logging__cleanup` at script exit.
#
# Args:
#   [<name>]  Path of the subdirectory to create under `_LOGGING__SYSSET_TMPDIR` (may
#             contain `/` for nested paths, e.g. `install/jq`). When omitted,
#             returns `_LOGGING__SYSSET_TMPDIR` itself (ensuring it is initialised).
#
# Stdout: absolute path to the named subdirectory (or `_LOGGING__SYSSET_TMPDIR` when called with no args).
# shellcheck disable=SC2120  # callers in other sourced files are invisible to shellcheck
file__tmpdir() {
  [[ -z "${_LOGGING__SYSSET_TMPDIR:-}" ]] && _LOGGING__SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/devfeats_XXXXXX")"
  if [[ -n "${1:-}" ]]; then
    mkdir -p "${_LOGGING__SYSSET_TMPDIR}/${1}"
    printf '%s\n' "${_LOGGING__SYSSET_TMPDIR}/${1}"
  else
    printf '%s\n' "${_LOGGING__SYSSET_TMPDIR}"
  fi
  return 0
}

# @brief file__mktmpdir <label> — Create and return a new unique directory under `_LOGGING__SYSSET_TMPDIR`.
#
# Unlike `file__tmpdir`, each call creates a distinct directory via `mktemp`.
# Use when per-call isolation is required (e.g. GPG homedirs, OCI pull dirs
# that may be called multiple times with different artifacts). The directory
# is cleaned up automatically when `logging__cleanup` removes `_LOGGING__SYSSET_TMPDIR`.
#
# Args:
#   <label>  Short label used as a prefix in the directory name.
#
# Stdout: absolute path to the new unique directory.
file__mktmpdir() {
  local _base
  # shellcheck disable=SC2119  # intentionally called without args to get the base dir
  _base="$(file__tmpdir)/${1:-tmp}"
  mkdir -p "${_base%/*}"
  mktemp -d "${_base}.XXXXXX"
}
