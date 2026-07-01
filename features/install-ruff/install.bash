# shellcheck shell=bash

# Write the cargo-dist install receipt that mirrors the standalone installer.
# Ruff reads it from ${XDG_CONFIG_HOME:-$HOME/.config}/ruff/ruff-receipt.json.
# shellcheck disable=SC2329,SC2317
__configure_user() {
  local _user="$1"
  local _xdg_config
  # shellcheck disable=SC2016
  _xdg_config="$(users__expand_path --user "$_user" '${XDG_CONFIG_HOME:-${HOME}/.config}')" || {
    logging__warn "Could not resolve XDG_CONFIG_HOME for '${_user}'; skipping ruff receipt."
    return 0
  }
  local _receipt_dir="${_xdg_config}/ruff"
  local _receipt_path="${_receipt_dir}/ruff-receipt.json"
  file__mkdir "${_receipt_dir}"
  printf '%s\n' \
    "{\"binaries\":[\"ruff\"],\"binary_aliases\":{},\"cdylibs\":[],\"cstaticlibs\":[],\"install_layout\":\"flat\",\"install_prefix\":\"${_RESOLVED_PREFIX}/bin\",\"modify_path\":false,\"provider\":{\"source\":\"cargo-dist\",\"version\":\"0.31.0\"},\"source\":{\"app_name\":\"ruff\",\"name\":\"ruff\",\"owner\":\"astral-sh\",\"release_type\":\"github\"},\"version\":\"${VERSION:-}\"}" \
    > "${_receipt_path}"
  file__chown "${_user}:${_user}" "${_receipt_dir}" "${_receipt_path}" 2> /dev/null || true
  logging__install "Wrote ruff install receipt → ${_receipt_path}"
}
