if os__is_devcontainer_build; then
  install__copy_bin "${_FEAT_FILES_DIR}/on-create--symlink-config-dir.sh" \
    "${_FEAT_LIFECYCLE_ON_CREATE}symlink-config-dir.sh"
  printf 'CONFIG_DIR="%s"\n' "${CONFIG_DIR}" \
    > "${_FEAT_LIFECYCLE_ON_CREATE}symlink-config-dir.sh.conf"
fi
