if os__is_devcontainer_build; then
  install__copy_bin "${_FEAT_FILES_DIR}/on-create--symlink-codex-dir.sh" \
    "${_FEAT_LIFECYCLE_ON_CREATE}symlink-codex-dir.sh"
  printf 'CODEX_HOME="%s"\n' "${CODEX_HOME}" \
    > "${_FEAT_LIFECYCLE_ON_CREATE}symlink-codex-dir.sh.conf"
fi
