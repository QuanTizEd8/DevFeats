if os__is_devcontainer_build; then
  _ON_CREATE_SCRIPT_NAME="lifecycle--on-create--symlink-vscode-user-dir.sh"
  _ON_CREATE_SCRIPT_DEST="${_LIFECYCLE_SCRIPT_DIR}/${_ON_CREATE_SCRIPT_NAME}"
  install__copy_bin "${_FILES_DIR}/${_ON_CREATE_SCRIPT_NAME}" "$_ON_CREATE_SCRIPT_DEST"
  printf 'VSCODE_USER_DIR="%s"\n' "${VSCODE_USER_DIR}" \
    > "${_LIFECYCLE_SCRIPT_DIR}/${_ON_CREATE_SCRIPT_NAME}.conf"
fi
