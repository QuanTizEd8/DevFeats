# shellcheck shell=bash
# helpers/common.bash — loaded in setup() of every .bats file.
#
# Sets LIB_ROOT, configures BATS_LIB_PATH, loads bats-support/-assert/-file,
# and defines the reload_lib() helper.

# LIB_ROOT: canonical lib/ directory.
# REPO_ROOT is exported by the test runner; fall back to git for direct invocation.
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
fi
LIB_ROOT="${REPO_ROOT}/lib"

# Point bats library loader at the vendored bats/ subdirectory.
export BATS_LIB_PATH="${REPO_ROOT}/test/lib/bats"

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# Pre-declare global associative/indexed arrays before sourcing modules.
# 'declare -A' without -g inside a function chain creates a local variable that
# disappears when the chain returns; '-g' ensures the global is created.
declare -gA _OSPKG__OS_RELEASE=()
declare -gA _OCI__AUTH_USER=()
declare -gA _OCI__AUTH_TOKEN=()
declare -gA _OCI__AUTH_DONE=()
declare -ga _LOGGING__SYSSET_MASKED_VALUES=()

# Source lib once at test-process startup.
# shellcheck source=/dev/null
source "${LIB_ROOT}/__init__.bash"

# reload_lib [<module.sh>]
#
# Resets all cached globals so a test can inject stubs and observe fresh
# behaviour. The module argument is accepted for backward compatibility but
# ignored: all modules are already loaded at process startup.
reload_lib() {
  # Reset os.sh lazy-cached globals.
  unset _OS__KERNEL _OS__ARCH _OS__ID _OS__ID_LIKE _OS__CODENAME _OS__PLATFORM _OS__RELEASE_LOADED

  # Reset net.sh cached state.
  unset _NET__FETCH_TOOL _NET__CA_CERTS_OK

  # Reset ospkg.sh detection flag.
  _OSPKG__DETECTED=false

  # Reset logging state flags.
  _LOGGING__LIB_SETUP=false
  _LOGGING__SYSSET_TMPDIR=
  declare -ga _LOGGING__SYSSET_MASKED_VALUES=()

  # Re-declare global associative arrays so prior test runs don't leave stale
  # entries (also guards against any code path that might 'unset' them).
  declare -gA _OSPKG__OS_RELEASE=()
  declare -gA _OCI__AUTH_USER=()
  declare -gA _OCI__AUTH_TOKEN=()
  declare -gA _OCI__AUTH_DONE=()
}
