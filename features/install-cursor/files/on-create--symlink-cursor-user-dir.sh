#!/bin/sh

symlink_cursor_user_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"

  # Skip when cursor_user_dir option was left empty.
  [ -n "${CURSOR_USER_DIR}" ] || return 0

  _cursor_user_dir_fullpath="${_container_workspace_folder}/${CURSOR_USER_DIR}"

  rm -rf ~/.cursor-server/data/User
  mkdir -p ~/.cursor-server/data
  mkdir -p "$_cursor_user_dir_fullpath"
  ln -s "$_cursor_user_dir_fullpath" ~/.cursor-server/data/User
}

symlink_cursor_user_dir "$1"
