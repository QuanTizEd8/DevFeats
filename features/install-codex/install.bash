# shellcheck shell=bash

# Resolve the bare version from the npm registry and set the GitHub release tag.
# The Codex GitHub releases use the tag format "rust-v{VERSION}" (e.g. rust-v0.130.0),
# which differs from the default "v{VERSION}" fallback, so we must set
# _FEAT_RESOLVED_TAG explicitly for the script-method asset URI substitution.
__resolve_version() {
  logging__inspect "Resolving Codex version from npm registry."
  local _ver
  _ver="$(npm__resolve_version_uri "${VERSION_URI}" "${VERSION}")"
  declare -g _FEAT_RESOLVED_TAG="rust-v${_ver}"
  logging__info "Resolved Codex version to '${_ver}' (tag='${_FEAT_RESOLVED_TAG}')."
  printf '%s\n' "${_ver}"
}

# Auto-resolve METHOD=auto.
# Prefer npm when Node.js is already present; fall back to the standalone
# installer script on Linux/macOS, or Homebrew cask on macOS.
__resolve_method() {
  logging__inspect "Resolving METHOD=auto for Codex."
  if command -v npm > /dev/null 2>&1; then
    logging__info "Resolved METHOD=auto → 'npm' (npm on PATH)."
    printf 'npm\n'
  elif command -v brew > /dev/null 2>&1; then
    logging__info "Resolved METHOD=auto → 'package' (Homebrew available)."
    printf 'package\n'
  else
    logging__info "Resolved METHOD=auto → 'script' (standalone installer)."
    printf 'script\n'
  fi
}

# Ensure npm is on PATH before the template auto-impl runs.
__install_run_npm_pre() {
  if command -v npm > /dev/null 2>&1; then
    logging__skip "npm already on PATH; skipping bootstrap install."
    return 0
  fi
  logging__install "Ensuring npm is available for Codex npm method."
  bootstrap__npm
}

# Configure the standalone installer before it runs:
#  - Pass the resolved version via --release.
#  - When running as root (devcontainer image build), place the binary package
#    under the feature's share directory so it is not overwritten when the
#    per-user lifecycle hook symlinks ~/.codex to the workspace .codex dir.
#  - Set CODEX_INSTALL_DIR to /usr/local/bin so the command link is on PATH.
__install_run_script_pre() {
  logging__install "Preparing Codex standalone installer (VERSION='${VERSION}')."
  _FEAT_INSTALL_SCRIPT_ARGS=(--release "${VERSION}")
  if [[ "$(id -u)" == "0" ]]; then
    export CODEX_INSTALL_DIR="/usr/local/bin"
    # Isolate the binary package from ~/.codex so the per-user symlink hook
    # (which removes and recreates ~/.codex) does not break the install.
    export CODEX_HOME="${_FEAT_SHARE_DIR_ROOT}/standalone"
    logging__info "Root install: CODEX_HOME='${CODEX_HOME}', CODEX_INSTALL_DIR='${CODEX_INSTALL_DIR}'."
  fi
}

# Override the package method to use the Homebrew cask (brew install --cask codex),
# which is the supported distribution channel on macOS.
__install_run_package__() {
  logging__install "Installing Codex via Homebrew cask."
  command -v brew > /dev/null 2>&1 || {
    logging__error "Homebrew is required for method=package."
    return 1
  }
  brew install --cask codex
  logging__success "Codex Homebrew cask install finished."
}
