if os__is_devcontainer_build; then
  install__copy_bin "${_FEAT_FILES_DIR}/on-create--symlink-claude-dir.sh" \
    "${_FEAT_LIFECYCLE_ON_CREATE}symlink-claude-dir.sh"
  printf 'CLAUDE_CONFIG_DIR="%s"\n' "${CLAUDE_CONFIG_DIR}" \
    > "${_FEAT_LIFECYCLE_ON_CREATE}symlink-claude-dir.sh.conf"
fi
