# shellcheck shell=bash

# Resolve the bare version from the npm registry and set the GitHub release tag.
# The Codex GitHub releases use the tag format "rust-v{VERSION}" (e.g. rust-v0.130.0),
# which differs from the default "v{VERSION}" fallback, so we must set
# _FEAT_RESOLVED_TAG explicitly for the script-method asset URI substitution.
__resolve_version() {
  local _ver
  _ver="$(npm__resolve_version_uri "${VERSION_URI}" "${VERSION}")" || return 1
  declare -g _FEAT_RESOLVED_TAG="rust-v${_ver}"
  printf '%s\n' "${_ver}"
}

# Auto-resolve METHOD=auto.
# Prefer npm when Node.js is already present; fall back to the standalone
# installer script on Linux/macOS, or Homebrew cask on macOS.
__resolve_method() {
  if command -v npm > /dev/null 2>&1; then
    printf 'npm\n'
  elif command -v brew > /dev/null 2>&1; then
    printf 'package\n'
  else
    printf 'script\n'
  fi
}

# Ensure npm is on PATH before the template auto-impl runs.
__install_run_npm_pre() {
  command -v npm > /dev/null 2>&1 && return 0
  ospkg__install_user nodejs npm || ospkg__install_user nodejs || {
    logging__error "install-codex: npm is required for method=npm but could not be installed."
    return 1
  }
  command -v npm > /dev/null 2>&1
}

# Configure the standalone installer before it runs:
#  - Pass the resolved version via --release.
#  - When running as root (devcontainer image build), place the binary package
#    under the feature's share directory so it is not overwritten when the
#    per-user lifecycle hook symlinks ~/.codex to the workspace .codex dir.
#  - Set CODEX_INSTALL_DIR to /usr/local/bin so the command link is on PATH.
__install_run_script_pre() {
  _FEAT_INSTALL_SCRIPT_ARGS=(--release "${VERSION}")
  if [[ "$(id -u)" == "0" ]]; then
    export CODEX_INSTALL_DIR="/usr/local/bin"
    # Isolate the binary package from ~/.codex so the per-user symlink hook
    # (which removes and recreates ~/.codex) does not break the install.
    export CODEX_HOME="${_FEAT_SHARE_DIR_ROOT}/standalone"
  fi
}

# Override the package method to use the Homebrew cask (brew install --cask codex),
# which is the supported distribution channel on macOS.
__install_run_package__() {
  command -v brew > /dev/null 2>&1 || {
    logging__error "install-codex: Homebrew is required for method=package."
    return 1
  }
  brew install --cask codex
}
