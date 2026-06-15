# shellcheck shell=bash

# Run the official install.sh with the resolved version and install prefix as
# env vars. The script expects VERSION as a v-prefixed tag (e.g. v1.0.48) and
# PREFIX as the install root; it places the binary at ${PREFIX}/bin/copilot.
__install_run_script_run() {
  logging__launch "Running Copilot installer script '$1'."
  local _script_path="$1"
  local _script_version="v${VERSION#v}"
  if [[ -v _RESOLVED_PREFIX ]]; then
    VERSION="${_script_version}" PREFIX="${_RESOLVED_PREFIX}" bash "${_script_path}" || {
      logging__error "Copilot installer script failed (prefix='${_RESOLVED_PREFIX}')."
      return 1
    }
  else
    VERSION="${_script_version}" bash "${_script_path}" || {
      logging__error "Copilot installer script failed."
      return 1
    }
  fi
}
