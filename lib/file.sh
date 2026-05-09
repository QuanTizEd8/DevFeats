#!/usr/bin/env bash
# File and archive helpers: extract `.tar.xz`, `.tar.gz`, `.tgz`, and `.zip` archives.
#
# Returns 1 on unrecognized format or missing extraction tool.

[ -n "${_FILE__LIB_LOADED-}" ] && return 0
_FILE__LIB_LOADED=1

_FILE__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_FILE__LIB_DIR/ospkg.sh"

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

# _file__ensure_extract_tool <ext> (internal)
# Ensures the extraction tool for <ext> is available; installs it via ospkg when possible.
# <ext>: "zip" (installs unzip), "xz" (installs xz-utils/xz), "gz" (installs gzip), "tar" (installs tar).
_file__ensure_extract_tool() {
  local _ext="$1"
  case "$_ext" in
    zip)
      command -v unzip > /dev/null 2>&1 && return 0
      ospkg__install_tracked "lib-file" unzip || true
      command -v unzip > /dev/null 2>&1 && return 0
      logging__error "file.sh: unzip is required to extract .zip archives but could not be installed."
      return 1
      ;;
    xz)
      command -v xz > /dev/null 2>&1 && return 0
      ospkg__run --manifest "$_FILE__XZ_MANIFEST" --build-group "lib-file" --skip_installed || true
      command -v xz > /dev/null 2>&1 && return 0
      logging__error "file.sh: xz is required to extract .tar.xz archives but could not be installed."
      return 1
      ;;
    gz)
      command -v gzip > /dev/null 2>&1 && return 0
      ospkg__install_tracked "lib-file" gzip || true
      command -v gzip > /dev/null 2>&1 && return 0
      logging__error "file.sh: gzip is required to extract .tar.gz archives but could not be installed."
      return 1
      ;;
    tar)
      command -v tar > /dev/null 2>&1 && return 0
      ospkg__install_tracked "lib-file" tar || true
      command -v tar > /dev/null 2>&1 && return 0
      logging__error "file.sh: tar is required but could not be installed."
      return 1
      ;;
    *)
      return 0
      ;;
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
      --owner) _owner="$2"; shift 2 ;;
      --group) _group="$2"; shift 2 ;;
      --mode) _mode="$2"; shift 2 ;;
      *) _dirs+=("$1"); shift ;;
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
  "${_cmd[@]}" "${_dirs[@]}"
}

# @brief file__extract_archive <archive_file> <dest_dir> [<original_name>] [--strip N] — Extract a `.tar.xz`, `.tar.gz`, `.tgz`, or `.zip` archive to `<dest_dir>`.
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
