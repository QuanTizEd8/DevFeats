if os__is_devcontainer_build; then
  _ON_CREATE_SCRIPT_NAME="on-create--symlink-claude-dir.sh"
  _ON_CREATE_SCRIPT_DEST="${_LIFECYCLE_SCRIPT_DIR}/${_ON_CREATE_SCRIPT_NAME}"
  install__copy_bin "${_FILES_DIR}/${_ON_CREATE_SCRIPT_NAME}" "$_ON_CREATE_SCRIPT_DEST"
  printf 'CLAUDE_CONFIG_DIR="%s"\n' "${CLAUDE_CONFIG_DIR}" \
    > "${_LIFECYCLE_SCRIPT_DIR}/${_ON_CREATE_SCRIPT_NAME}.conf"
fi
