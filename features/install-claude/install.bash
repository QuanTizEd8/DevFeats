# shellcheck shell=bash

# binary: fetch the per-version manifest to obtain the platform checksum, then
# set BINARY_SHA256 so the template's __install_run_binary__ can verify the download.
# shellcheck disable=SC2329,SC2317
__install_run_binary_pre() {
  local _platform
  _platform="$(ctx__expand_pattern \
    "{plat.kernel:lower}-{plat.machine_node}{plat.kernel==linux?{plat.libc==musl?-musl:}:}")"
  local _manifest_url="https://downloads.claude.ai/claude-code-releases/${VERSION}/manifest.json"
  local _tmpfile
  _tmpfile="$(mktemp)"
  uri__fetch_asset "${_manifest_url}" --file-dest "${_tmpfile}" --sha256 none > /dev/null 2>&1 || {
    rm -f "${_tmpfile}"
    logging__error "Failed to fetch Claude Code manifest from '${_manifest_url}'."
    return 1
  }
  declare -g BINARY_SHA256
  BINARY_SHA256="$(json__query -r ".platforms[\"${_platform}\"].checksum // empty" < "${_tmpfile}")"
  rm -f "${_tmpfile}"
  [[ -n "${BINARY_SHA256}" ]] || {
    logging__error "Platform '${_platform}' not found in Claude Code manifest."
    return 1
  }
}
