#!/usr/bin/env bash
set -euo pipefail

_FEAT_ID="@@FEATURE_ID@@"
_FEAT_VERSION="@@FEATURE_VERSION@@"
_FEAT_NAME="@@FEATURE_NAME@@"
_FEAT_SHARE_DIR="@@FEATURE_SHARE_DIR@@"
_EXPORT_PROFILE_D="@@FEATURE_PROFILE_D_FILE@@"

# Path to the feature's root directory.
_BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Path to the feature's ``files/`` sub-directory.
_FILES_DIR="${_BASE_DIR}/files"

_SYSSET_BUILD_CONTEXT="${_SYSSET_BUILD_CONTEXT:-feature::$_FEAT_ID}"
export _SYSSET_BUILD_CONTEXT

# shellcheck source=lib/logging.sh
. "$_BASE_DIR/_lib/logging.sh"
# shellcheck source=lib/os.sh
. "$_BASE_DIR/_lib/os.sh"
# shellcheck source=lib/str.sh
. "$_BASE_DIR/_lib/str.sh"
# shellcheck source=lib/ver.sh
. "$_BASE_DIR/_lib/ver.sh"
# shellcheck source=lib/json.sh
. "$_BASE_DIR/_lib/json.sh"
# shellcheck source=lib/net.sh
. "$_BASE_DIR/_lib/net.sh"
# shellcheck source=lib/file.sh
. "$_BASE_DIR/_lib/file.sh"
# shellcheck source=lib/verify.sh
. "$_BASE_DIR/_lib/verify.sh"
# shellcheck source=lib/lock.sh
. "$_BASE_DIR/_lib/lock.sh"
# shellcheck source=lib/git.sh
. "$_BASE_DIR/_lib/git.sh"
# shellcheck source=lib/users.sh
. "$_BASE_DIR/_lib/users.sh"
# shellcheck source=lib/proc.sh
. "$_BASE_DIR/_lib/proc.sh"
# shellcheck source=lib/graph.sh
. "$_BASE_DIR/_lib/graph.sh"
# shellcheck source=lib/shell.sh
. "$_BASE_DIR/_lib/shell.sh"
# shellcheck source=lib/install/common.sh
. "$_BASE_DIR/_lib/install/common.sh"
# shellcheck source=lib/install/jq.sh
. "$_BASE_DIR/_lib/install/jq.sh"
# shellcheck source=lib/install/yq.sh
. "$_BASE_DIR/_lib/install/yq.sh"
# shellcheck source=lib/install/oras.sh
. "$_BASE_DIR/_lib/install/oras.sh"
# shellcheck source=lib/ospkg.sh
. "$_BASE_DIR/_lib/ospkg.sh"
# shellcheck source=lib/github.sh
. "$_BASE_DIR/_lib/github.sh"
# shellcheck source=lib/oci.sh
. "$_BASE_DIR/_lib/oci.sh"
# shellcheck source=lib/uri.sh
. "$_BASE_DIR/_lib/uri.sh"

logging__setup
logging__feature_entry "$_FEAT_NAME v$_FEAT_VERSION"

# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329,SC2317
_cleanup_hook() { return; }

# Override _prefix_post_install to add supplemental post-install steps
# (e.g. exporting additional env vars). The generated block replaces this
# stub with the real implementation when _prefix_groups is declared.
# shellcheck disable=SC2329,SC2317
_prefix_post_install() { return; }

# shellcheck disable=SC2329,SC2317
_on_exit() {
  local _rc=$?
  _cleanup_hook
  [[ $_rc -eq 0 ]] && _prefix_post_install
  if [[ "${KEEP_CACHE:-true}" != true ]]; then
    if users__is_privileged || [[ "$(os__kernel)" == "Darwin" ]]; then
      ospkg__clean
    else
      logging__info "Skipping package-manager cache cleanup (no privilege available)."
    fi
  fi
  [[ "${KEEP_BUILD_DEPS:-false}" != true ]] && [[ -z "${_SYSSET_SESSION_TRACK_DIR:-}" ]] && ospkg__cleanup_all_build_groups
  if [[ $_rc -eq 0 ]]; then
    logging__success "$_FEAT_NAME script finished successfully."
  else
    logging__fatal "$_FEAT_NAME script exited with error ${_rc}."
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT
