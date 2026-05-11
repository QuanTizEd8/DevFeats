#!/bin/sh

warn() { printf 'install-cursor postCreateCommand: WARN: %s\n' "$*" >&2; }
die() {
  printf 'install-cursor postCreateCommand: ERROR: %s\n' "$*" >&2
  exit 1
}

# Source runtime configuration written by the installer at image-build time.
_CONF="/usr/local/share/repodynamics/devfeats/install-cursor/lifecycle--on-create--symlink-cursor-user-dir.sh.conf"
[ -f "$_CONF" ] || die "runtime config not found: ${_CONF}"
# shellcheck source=/dev/null
. "$_CONF"

symlink_cursor_user_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"
  _cursor_user_dir_fullpath="${_container_workspace_folder}/${CURSOR_USER_DIR}"

  rm -rf ~/.cursor-server/data/User
  mkdir -p ~/.cursor-server/data
  mkdir -p "$_cursor_user_dir_fullpath"
  ln -s "$_cursor_user_dir_fullpath" ~/.cursor-server/data/User
}

symlink_cursor_user_dir "$1"
