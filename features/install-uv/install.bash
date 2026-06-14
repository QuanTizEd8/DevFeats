# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# After install__release_asset installs 'uv' from the archive, also copy 'uvx'
# from the same extracted tree.  Both binaries live in the top-level directory
# of the tarball (e.g. uv-x86_64-unknown-linux-musl/uvx).
# shellcheck disable=SC2329,SC2317
__install_run_binary_post() {
  local _uvx_src
  _uvx_src="$(find "${INSTALLER_DIR}/asset" -name "uvx" -type f 2> /dev/null | head -1)"
  if [[ -n "${_uvx_src}" ]]; then
    install -m 0755 "${_uvx_src}" "${_RESOLVED_PREFIX}/bin/uvx"
    logging__install "Installed uvx → ${_RESOLVED_PREFIX}/bin/uvx"
  else
    logging__warn "uvx binary not found in archive; skipping uvx installation."
  fi
}

# Run the official uv installer script with UV_UNMANAGED_INSTALL pointing to
# PREFIX/bin so that both 'uv' and 'uvx' land there.  UV_UNMANAGED_INSTALL
# also disables shell-profile PATH mutation and updater receipt installation,
# which is correct for devcontainer and CI environments.
# shellcheck disable=SC2329,SC2317
__install_run_script_run() {
  logging__launch "Running uv installer script '$1' (UV_UNMANAGED_INSTALL='${UV_UNMANAGED_INSTALL:-}')."
  local _script_path="$1"
  file__mkdir "${_RESOLVED_PREFIX}/bin"
  UV_UNMANAGED_INSTALL="${_RESOLVED_PREFIX}/bin" "${_script_path}"
}
