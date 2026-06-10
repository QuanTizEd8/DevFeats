# shellcheck shell=bash

# Binary releases are published only for x64 (amd64) and arm64.
# Fall back to npm on other architectures (requires Node.js 22+).
__resolve_method() {
  logging__inspect "Resolving METHOD=auto for Copilot CLI."
  case "$(os__release_arch)" in
    amd64 | arm64)
      logging__info "Resolved METHOD=auto → 'binary'."
      printf 'binary\n'
      ;;
    *)
      logging__info "Resolved METHOD=auto → 'npm' (unsupported arch)."
      printf 'npm\n'
      ;;
  esac
}

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

# Ensure npm is on PATH before the template auto-impl runs (method=npm).
__install_run_npm_pre() {
  if command -v npm > /dev/null 2>&1; then
    logging__skip "npm already on PATH; skipping bootstrap install."
    return 0
  fi
  logging__install "Ensuring npm is available for Copilot npm method."
  npm__ensure_npm
}
