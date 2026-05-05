#!/usr/bin/env bash
# Git helpers: shallow clone and other repository operations.
#
# `git__clone` performs a `--depth=1` clone and is idempotent: it skips the
# clone if the target directory already contains a `.git` directory.

[[ -n "${_GIT__LIB_LOADED-}" ]] && return 0
_GIT__LIB_LOADED=1

_GIT__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_GIT__LIB_DIR/ospkg.sh"

# @brief git__clone --url <url> --dir <dir> [--branch <branch>] — Shallow clone (`--depth=1`) of `<url>` into `<dir>`. Idempotent: skips if `<dir>/.git` already exists.
#
# On failure, the partially-created `<dir>` is removed so that a re-run does
# not silently skip a broken clone.
#
# Args:
#   --url <url>        Repository URL to clone.
#   --dir <dir>        Local destination directory.
#   --branch <branch>  Branch or tag to check out (optional; defaults to HEAD).
#
# Returns: 0 on success or if already cloned, 1 on failure.
git__clone() {
  local branch="" dir="" url=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch)
        shift
        branch="$1"
        shift
        ;;
      --dir)
        shift
        dir="$1"
        shift
        ;;
      --url)
        shift
        url="$1"
        shift
        ;;
      --*)
        logging__error "git__clone: unknown option '${1}'"
        return 1
        ;;
      *)
        logging__error "git__clone: unexpected argument '${1}'"
        return 1
        ;;
    esac
  done
  [ -z "${dir}" ] && {
    logging__error "git__clone: missing --dir"
    return 1
  }
  [ -z "${url}" ] && {
    logging__error "git__clone: missing --url"
    return 1
  }

  if [ -d "${dir}/.git" ]; then
    logging__info "'${dir}' already exists — skipping clone."
    return 0
  fi

  # Auto-provision git if not yet available (idempotent if already installed).
  ospkg__install_tracked "lib-git" git || {
    logging__error "git could not be installed."
    return 1
  }

  mkdir -p "$dir"
  local _clone_args=(--depth=1
    -c core.eol=lf
    -c core.autocrlf=false
    -c fsck.zeroPaddedFilemode=ignore
    -c fetch.fsck.zeroPaddedFilemode=ignore
    -c receive.fsck.zeroPaddedFilemode=ignore)
  [ -n "${branch}" ] && _clone_args+=(--branch "$branch")

  if ! git clone "${_clone_args[@]}" "$url" "$dir" 2>&1; then
    rm -rf "$dir" 2> /dev/null || true
    logging__error "git clone of '${url}' failed."
    return 1
  fi
  return 0
}
