#!/bin/sh

warn() { printf 'install-copilot postCreateCommand: WARN: %s\n' "$*" >&2; }
die() {
  printf 'install-copilot postCreateCommand: ERROR: %s\n' "$*" >&2
  exit 1
}

# Source runtime configuration written by the installer at image-build time.
_CONF="/usr/local/share/repodynamics/devfeats/install-copilot/lifecycle--on-create--symlink-vscode-user-dir.sh.conf"
[ -f "$_CONF" ] || die "runtime config not found: ${_CONF}"
# shellcheck source=/dev/null
. "$_CONF"

symlink_vscode_user_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"
  _vscode_user_dir_fullpath="${_container_workspace_folder}/${VSCODE_USER_DIR}"

  rm -rf ~/.vscode-server/data/User
  mkdir -p ~/.vscode-server/data
  mkdir -p "$_vscode_user_dir_fullpath"
  ln -s "$_vscode_user_dir_fullpath" ~/.vscode-server/data/User
}

symlink_vscode_user_dir "$1"
