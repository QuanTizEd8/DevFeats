#!/usr/bin/env bash
# log_file: log_file=/tmp/brew-macos-test.log — installer output is mirrored to
# the specified file in addition to stdout/stderr.
#
# Cleanup: removes the log file and shellenv blocks on EXIT.
set -e

source dev-container-features-test-lib

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_HOME="$HOME"
_LOG_FILE="/tmp/brew-macos-test-$$.log"

_cleanup() {
  rm -f "$_LOG_FILE"
  for f in "${_HOME}/.bash_profile" "${_HOME}/.bash_login" "${_HOME}/.profile" \
    "${_HOME}/.bashrc" "${_HOME}/.zprofile" "${_HOME}/.zshrc"; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

# --- run the feature ---
bash "${REPO_ROOT}/src/install-homebrew/install.sh" \
  --log_file "$_LOG_FILE"

# --- brew is intact ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- log file written ---
echo "===== ${_LOG_FILE} (last 20 lines) ====="
tail -20 "$_LOG_FILE" 2> /dev/null || echo "(missing)"
check "log_file was created" test -f "$_LOG_FILE"
check "log_file is non-empty" test -s "$_LOG_FILE"
check "log_file contains install-homebrew header" grep -q 'install-homebrew' "$_LOG_FILE"
check "log_file contains success marker" grep -q 'Homebrew Installation script finished successfully' "$_LOG_FILE"
check "log_file contains brew prefix path" grep -qF "$_BREW_PREFIX" "$_LOG_FILE"

reportResults
