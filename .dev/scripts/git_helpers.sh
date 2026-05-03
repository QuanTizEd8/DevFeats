#!/usr/bin/env bash

[[ -n "${_SCRIPTS_GIT_HELPERS_LOADED-}" ]] && return 0
_SCRIPTS_GIT_HELPERS_LOADED=1

_SCRIPTS_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_git__run() {
  git -C "${_SCRIPTS_HELPERS_DIR}" "$@"
}

git__die() {
  printf '⛔ %s\n' "$*" >&2
  exit 1
}

# Return repository root for the current git worktree.
git__repo_root() {
  local _root
  _root="$(_git__run rev-parse --show-toplevel 2> /dev/null || true)"
  if [[ -z "${_root}" ]]; then
    return 1
  fi
  printf '%s\n' "${_root}"
  return 0
}

# Return origin remote URL.
git__origin_url() {
  local _url
  _url="$(_git__run config --get remote.origin.url 2> /dev/null || true)"
  if [[ -z "${_url}" ]]; then
    return 1
  fi
  printf '%s\n' "${_url}"
  return 0
}

# Return GitHub slug in owner/repo format.
git__origin_slug() {
  local _url
  local _owner
  local _repo

  _url="$(git__origin_url || true)"
  if [[ -z "${_url}" ]]; then
    return 1
  fi

  # bash =~ ERE: `+?` (non-greedy) is invalid on some systems (e.g. macOS).
  if [[ "${_url}" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
    _owner="${BASH_REMATCH[1]}"
    _repo="${BASH_REMATCH[2]}"
    # e.g. https://.../owner/Repo.git — [^/]+ is greedy, so the repo often includes ".git"
    # here; the API and gh need the bare repo name.
    _repo="${_repo%.git}"
    printf '%s/%s\n' "${_owner}" "${_repo}"
    return 0
  fi

  return 1
}

# Return GitHub owner from origin URL.
git__origin_owner() {
  local _slug
  _slug="$(git__origin_slug || true)"
  if [[ -z "${_slug}" ]]; then
    return 1
  fi
  printf '%s\n' "${_slug%%/*}"
  return 0
}

# Return GitHub repository name from origin URL.
git__origin_name() {
  local _slug
  _slug="$(git__origin_slug || true)"
  if [[ -z "${_slug}" ]]; then
    return 1
  fi
  printf '%s\n' "${_slug#*/}"
  return 0
}

git__require_repo_root() {
  local _root
  _root="$(git__repo_root || true)"
  if [[ -z "${_root}" ]]; then
    git__die "Could not determine repository root (run from inside a git worktree)."
  fi
  printf '%s\n' "${_root}"
  return 0
}

git__require_origin_slug() {
  local _slug
  _slug="$(git__origin_slug || true)"
  if [[ -z "${_slug}" ]]; then
    git__die "Could not determine GitHub slug from git origin URL."
  fi
  printf '%s\n' "${_slug}"
  return 0
}

git__require_origin_owner() {
  local _owner
  _owner="$(git__origin_owner || true)"
  if [[ -z "${_owner}" ]]; then
    git__die "Could not determine GitHub owner from git origin URL."
  fi
  printf '%s\n' "${_owner}"
  return 0
}

git__require_origin_name() {
  local _name
  _name="$(git__origin_name || true)"
  if [[ -z "${_name}" ]]; then
    git__die "Could not determine GitHub repository name from git origin URL."
  fi
  printf '%s\n' "${_name}"
  return 0
}
