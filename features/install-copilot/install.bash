if os__is_devcontainer_build; then
  install__copy_bin "${_FEAT_FILES_DIR}/on-create--symlink-vscode-user-dir.sh" \
    "${_FEAT_LIFECYCLE_ON_CREATE}symlink-vscode-user-dir.sh"
  printf 'VSCODE_USER_DIR="%s"\n' "${VSCODE_USER_DIR}" \
    > "${_FEAT_LIFECYCLE_ON_CREATE}symlink-vscode-user-dir.sh.conf"
fi
