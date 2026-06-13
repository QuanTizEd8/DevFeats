# shellcheck shell=bash
# POSIX-compatible helper functions shared between install.sh (POSIX bootstrap
# phase) and install.bash (bash runtime phase via lib/__init__.bash).
#
# All functions in this file MUST be compatible with POSIX sh: no [[ ]],
# no bash arrays, no process substitution. Return 1 on failure; never exit.

posix__bootstrap_xcode() {
  # @brief posix__bootstrap_xcode — Ensure Xcode Command Line Tools are installed (macOS only).
  #
  # Headlessly installs the Xcode Command Line Tools via `softwareupdate` when
  # they are absent. This provides `make`, `cc`, and other build essentials
  # required for compiling software from source on macOS.
  #
  # No-op on non-macOS systems. Requires `sudo` privileges to install.
  #
  # Returns: 0 when CLTs are present (or successfully installed), 1 on failure.
  [ "$(uname -s)" = "Darwin" ] || return 0
  if xcode-select -p > /dev/null 2>&1; then
    logging__success "Xcode Command Line Tools already installed at '$(xcode-select -p 2> /dev/null)'."
    return 0
  fi
  logging__inspect "Xcode Command Line Tools not found — installing headlessly."
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  local _xcode_pkg
  _xcode_pkg="$(softwareupdate -l 2>&1 |
    grep -E '\*.*Command Line Tools' |
    tail -1 |
    sed 's/.*\* //')" || true
  if [ -z "$_xcode_pkg" ]; then
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    logging__error "No 'Command Line Tools' package found in softwareupdate -l."
    logging__info "Install manually with: xcode-select --install"
    return 1
  fi
  logging__install "Installing via softwareupdate: '${_xcode_pkg}'"
  if ! softwareupdate -i "$_xcode_pkg" --verbose; then
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    logging__error "softwareupdate failed to install '${_xcode_pkg}'."
    logging__info "Install manually with: xcode-select --install"
    return 1
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  logging__success "Xcode Command Line Tools installed."
  return 0
}
