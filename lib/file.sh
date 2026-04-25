#!/usr/bin/env bash
# Do not edit _lib/ copies directly — edit lib/ instead.

[ -n "${_FILE__LIB_LOADED-}" ] && return 0
_FILE__LIB_LOADED=1

_FILE__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_FILE__LIB_DIR/ospkg.sh"

# _file__ensure_extract_tool <ext> (internal)
# Ensures the extraction tool for <ext> is available; installs it via ospkg when possible.
# <ext>: "zip" (installs unzip), "tar" (hard-fail — system primitive).
_file__ensure_extract_tool() {
  local _ext="$1"
  case "$_ext" in
    zip)
      command -v unzip > /dev/null 2>&1 && return 0
      echo "ℹ️  unzip not found — installing." >&2
      ospkg__install_tracked "${_SYSSET_BUILD_CONTEXT:-uncontexted}::lib-file" unzip
      command -v unzip > /dev/null 2>&1 && return 0
      echo "⛔ file.sh: unzip is required to extract .zip archives but could not be installed." >&2
      return 1
      ;;
    tar)
      command -v tar > /dev/null 2>&1 && return 0
      echo "⛔ file.sh: tar is required but not found. Install it via your system package manager." >&2
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# @brief file__extract_archive <archive_file> <dest_dir> [<original_name>] — Extract a `.tar.xz`, `.tar.gz`, `.tgz`, or `.zip` archive to `<dest_dir>`. Returns 1 on unrecognized format or missing tool.
#
# <original_name> is used for format detection when <archive_file> is a temp
# path with no meaningful extension (e.g. a mktemp output). When omitted,
# the basename of <archive_file> is used.
#
# Args:
#   <archive_file>   Path to the archive to extract.
#   <dest_dir>       Destination directory (created if absent).
#   <original_name>  Optional filename used for extension-based format detection.
file__extract_archive() {
  local _arc="$1" _dest="$2"
  local _name="${3:-$(basename "$_arc")}"
  mkdir -p "$_dest"
  case "$_name" in
    *.tar.xz)
      _file__ensure_extract_tool tar || return 1
      tar -xJf "$_arc" -C "$_dest"
      ;;
    *.tar.gz | *.tgz)
      _file__ensure_extract_tool tar || return 1
      tar -xzf "$_arc" -C "$_dest"
      ;;
    *.zip)
      _file__ensure_extract_tool zip || return 1
      unzip -q -o "$_arc" -d "$_dest"
      ;;
    *)
      echo "⚠️  Unrecognized archive format: '$(basename "$_name")'. Skipping." >&2
      return 1
      ;;
  esac
  return 0
}
