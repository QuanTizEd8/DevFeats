if os__is_devcontainer_build; then
  install__copy_bin "${_FEAT_FILES_DIR}/on-create--symlink-cursor-user-dir.sh" \
    "${_FEAT_LIFECYCLE_ON_CREATE}symlink-cursor-user-dir.sh"
  printf 'CURSOR_USER_DIR="%s"\n' "${CURSOR_USER_DIR}" \
    > "${_FEAT_LIFECYCLE_ON_CREATE}symlink-cursor-user-dir.sh.conf"
fi
