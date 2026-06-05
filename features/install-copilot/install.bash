# shellcheck shell=bash

# Binary releases are published only for x64 (amd64) and arm64.
# Fall back to npm on other architectures (requires Node.js 22+).
__resolve_method() {
  case "$(os__release_arch)" in
    amd64 | arm64) printf 'binary\n' ;;
    *) printf 'npm\n' ;;
  esac
}

# Run the official install.sh with the resolved version and install prefix as
# env vars. The script expects VERSION as a v-prefixed tag (e.g. v1.0.48) and
# PREFIX as the install root; it places the binary at ${PREFIX}/bin/copilot.
__install_run_script_run() {
  local _script_path="$1"
  local _script_version="v${VERSION#v}"
  if [[ -v PREFIX && -n "${PREFIX}" ]]; then
    VERSION="${_script_version}" PREFIX="${PREFIX}" bash "${_script_path}"
  else
    VERSION="${_script_version}" bash "${_script_path}"
  fi
}
