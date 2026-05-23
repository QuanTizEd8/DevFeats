if os__is_devcontainer_build; then
  _ON_CREATE_SCRIPT_NAME="lifecycle--on-create--symlink-cursor-user-dir.sh"
  _ON_CREATE_SCRIPT_DEST="${_LIFECYCLE_SCRIPT_DIR}/${_ON_CREATE_SCRIPT_NAME}"
  install__copy_bin "${_FEAT_FILES_DIR}/${_ON_CREATE_SCRIPT_NAME}" "$_ON_CREATE_SCRIPT_DEST"
  printf 'CURSOR_USER_DIR="%s"\n' "${CURSOR_USER_DIR}" \
    > "${_LIFECYCLE_SCRIPT_DIR}/${_ON_CREATE_SCRIPT_NAME}.conf"
fi
