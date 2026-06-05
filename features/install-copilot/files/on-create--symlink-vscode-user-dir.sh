#!/bin/sh

symlink_vscode_user_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"

  # Skip when vscode_user_dir option was left empty.
  [ -n "${VSCODE_USER_DIR}" ] || return 0

  _vscode_user_dir_fullpath="${_container_workspace_folder}/${VSCODE_USER_DIR}"

  rm -rf ~/.vscode-server/data/User
  mkdir -p ~/.vscode-server/data
  mkdir -p "$_vscode_user_dir_fullpath"
  ln -s "$_vscode_user_dir_fullpath" ~/.vscode-server/data/User
}

symlink_vscode_user_dir "$1"
