# shellcheck source=lib/install/common.sh
. "${_BASE_DIR}/_lib/install/common.sh"
# shellcheck source=lib/os.sh
. "${_BASE_DIR}/_lib/os.sh"

if os__is_devcontainer_build; then
  _ON_CREATE_SCRIPT_NAME="lifecycle--on-create--symlink-codex-dir.sh"
  _ON_CREATE_SCRIPT_DEST="${_FEAT_SHARE_DIR}/${_ON_CREATE_SCRIPT_NAME}"
  install__copy_bin "${_FILES_DIR}/${_ON_CREATE_SCRIPT_NAME}" "$_ON_CREATE_SCRIPT_DEST"
  printf 'CODEX_HOME="%s"\n' "${CODEX_HOME}" \
    > "${_FEAT_SHARE_DIR}/${_ON_CREATE_SCRIPT_NAME}.conf"
fi
