_FILES_DIR="${_BASE_DIR}/files"

# shellcheck source=lib/os.sh
. "${_SELF_DIR}/_lib/os.sh"

if os__is_devcontainer_build; then
  _FEAT_SHARE_DIR="/usr/local/share/repodynamics/devfeats/install-codex"
  _ON_CREATE_SCRIPT_NAME="lifecycle--on-create--symlink-codex-dir.sh"
  _ON_CREATE_SCRIPT_DEST="${_FEAT_SHARE_DIR}/${_ON_CREATE_SCRIPT_NAME}"
  mkdir -p "$(dirname "$_ON_CREATE_SCRIPT_DEST")"
  cp "${_FILES_DIR}/${_ON_CREATE_SCRIPT_NAME}" "$_ON_CREATE_SCRIPT_DEST"
  chmod +x "$_ON_CREATE_SCRIPT_DEST"
  printf 'CODEX_HOME="%s"\n' "${CODEX_HOME}" \
    > "${_FEAT_SHARE_DIR}/${_ON_CREATE_SCRIPT_NAME}.conf"
fi
