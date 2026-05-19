# shellcheck source=lib/install/jq.sh
. "${_BASE_DIR}/_lib/install/jq.sh"
# shellcheck source=lib/shell.sh
. "${_BASE_DIR}/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "${_BASE_DIR}/_lib/github.sh"
# shellcheck source=lib/users.sh
. "${_BASE_DIR}/_lib/users.sh"

# _jq__resolve_version — resolve VERSION global to a bare semver string (no prefix).
# jq release tags use "jq-X.Y.Z" format rather than "vX.Y.Z".
_jq__resolve_version() {
  logging__fn_entry "_jq__resolve_version"
  local _spec="$VERSION"
  local _out
  _out="$(github__resolve_version "jqlang/jq" "$_spec")" || {
    logging__error "Failed to resolve jq version from GitHub."
    exit 1
  }
  VERSION="${_out#*$'\n'}"
  logging__info "Resolved version '${VERSION}'"
  logging__fn_exit "_jq__resolve_version"
  return 0
}

# _jq__get_installed_version <bin> — print bare semver of installed jq, or empty string.
_jq__get_installed_version() {
  local _bin="${1-}"
  [[ -x "${_bin}" ]] || return 0
  # jq --version prints "jq-X.Y.Z"; strip the leading "jq-".
  "${_bin}" --version 2> /dev/null | sed 's/^jq-//' || true
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Version is not meaningful for package; only resolve when actually needed.
if [[ "${METHOD}" != "package" ]]; then
  _jq__resolve_version
fi

# Install build dependencies before attempting a source build.
if [[ "${METHOD}" == "source" ]]; then
  _build_deps__install_source
fi

# Version-match idempotency: skip reinstall when the binary at the target
# location already matches the resolved version (regardless of if_exists).
_JQ_TARGET_BIN="${PREFIX}/bin/jq"
_INSTALLED_VER=""
if [[ "${METHOD}" != "package" ]] && [[ -x "${_JQ_TARGET_BIN}" ]]; then
  _INSTALLED_VER="$(_jq__get_installed_version "${_JQ_TARGET_BIN}")"
fi

_SKIP_INSTALL=false
if [[ -n "${_INSTALLED_VER}" && "${_INSTALLED_VER}" == "${VERSION}" ]]; then
  logging__info "jq ${VERSION} is already installed at '${_JQ_TARGET_BIN}' — skipping install."
  _SKIP_INSTALL=true
elif [[ "${METHOD}" != "package" ]] && [[ -x "${_JQ_TARGET_BIN}" ]]; then
  case "${IF_EXISTS}" in
    skip)
      logging__info "jq already installed at '${_JQ_TARGET_BIN}' (${_INSTALLED_VER:-unknown}) — skipping (if_exists=skip)."
      _SKIP_INSTALL=true
      ;;
    fail)
      logging__error "jq already installed at '${_JQ_TARGET_BIN}' (${_INSTALLED_VER:-unknown}) and if_exists=fail."
      exit 1
      ;;
    reinstall)
      logging__info "Removing existing jq binary at '${_JQ_TARGET_BIN}' (if_exists=reinstall)."
      rm -f "${_JQ_TARGET_BIN}"
      ;;
  esac
fi

if [[ "${_SKIP_INSTALL}" != "true" ]]; then
  install__jq \
    --context user \
    --owner-group "feature::install-jq" \
    --method "${METHOD}" \
    --if-exists "${IF_EXISTS}" \
    --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" \
    --prefix "${PREFIX}" \
    --version "${VERSION}" \
    --installer-dir "${INSTALLER_DIR}" > /dev/null
fi
if [[ "${METHOD}" == "auto" ]]; then
  if [[ -x "${PREFIX}/bin/jq" ]]; then
    METHOD=binary
  else
    METHOD=package
  fi
fi
