# shellcheck source=lib/install/jq.sh
. "${_SELF_DIR}/_lib/install/jq.sh"
# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"
# shellcheck source=lib/users.sh
. "${_SELF_DIR}/_lib/users.sh"

# _jq__resolve_version — resolve VERSION global to a bare semver string (no prefix).
# jq release tags use "jq-X.Y.Z" format rather than "vX.Y.Z".
_jq__resolve_version() {
  logging__fn_entry "_jq__resolve_version"
  if [[ "${VERSION}" == "latest" ]]; then
    local _tag
    _tag="$(github__latest_tag "jqlang/jq")" || {
      logging__error "Failed to fetch latest jq tag from GitHub."
      exit 1
    }
    # Strip either "jq-" or "v" prefix from the resolved tag.
    VERSION="${_tag#jq-}"
    VERSION="${VERSION#v}"
    logging__info "Resolved 'latest' to version '${VERSION}'"
  else
    VERSION="${VERSION#jq-}"
    VERSION="${VERSION#v}"
    if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      logging__error "Unrecognised version string '${VERSION}'. Expected X.Y.Z, vX.Y.Z, or jq-X.Y.Z."
      exit 1
    fi
  fi
  logging__fn_exit "_jq__resolve_version"
  return 0
}

# _jq__resolve_prefix — resolve PREFIX global from 'auto' to an absolute path.
_jq__resolve_prefix() {
  logging__fn_entry "_jq__resolve_prefix"
  if [[ -z "${PREFIX}" || "${PREFIX}" == "auto" ]]; then
    PREFIX="$(users__default_prefix)"
    logging__info "Resolved prefix to '${PREFIX}'"
  fi
  logging__fn_exit "_jq__resolve_prefix"
  return 0
}

# _jq__get_installed_version <bin> — print bare semver of installed jq, or empty string.
_jq__get_installed_version() {
  local _bin="${1-}"
  [[ -x "${_bin}" ]] || return 0
  # jq --version prints "jq-X.Y.Z"; strip the leading "jq-".
  "${_bin}" --version 2> /dev/null | sed 's/^jq-//' || true
}

# _jq__create_symlink — create symlink to ${PREFIX}/bin/jq in the canonical bin dir.
# Skipped for method=repos (package manager controls install location).
_jq__create_symlink() {
  logging__fn_entry "_jq__create_symlink"
  if [[ "${SYMLINK}" != "true" ]]; then
    logging__info "symlink=false; skipping symlink creation."
    logging__fn_exit "_jq__create_symlink"
    return 0
  fi
  if [[ "${METHOD}" == "repos" ]]; then
    logging__info "method=repos; symlink not applicable."
    logging__fn_exit "_jq__create_symlink"
    return 0
  fi
  if [[ ! -x "${PREFIX}/bin/jq" ]]; then
    logging__fn_exit "_jq__create_symlink"
    return 0
  fi
  shell__create_symlink \
    --src "${PREFIX}/bin/jq" \
    --system-target "/usr/local/bin/jq" \
    --user-target "${HOME}/.local/bin/jq"
  logging__fn_exit "_jq__create_symlink"
  return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

_jq__resolve_prefix

# Version is not meaningful for repos; only resolve when actually needed.
if [[ "${METHOD}" != "repos" ]]; then
  _jq__resolve_version
fi

# Install build dependencies before attempting a source build.
if [[ "${METHOD}" == "source" ]]; then
  _source_deps__install
fi

# Version-match idempotency: skip reinstall when the binary at the target
# location already matches the resolved version (regardless of if_exists).
_JQ_TARGET_BIN="${PREFIX}/bin/jq"
_INSTALLED_VER=""
if [[ "${METHOD}" != "repos" ]] && [[ -x "${_JQ_TARGET_BIN}" ]]; then
  _INSTALLED_VER="$(_jq__get_installed_version "${_JQ_TARGET_BIN}")"
fi

_SKIP_INSTALL=false
if [[ -n "${_INSTALLED_VER}" && "${_INSTALLED_VER}" == "${VERSION}" ]]; then
  logging__info "jq ${VERSION} is already installed at '${_JQ_TARGET_BIN}' — skipping install."
  _SKIP_INSTALL=true
elif [[ "${METHOD}" != "repos" ]] && [[ -x "${_JQ_TARGET_BIN}" ]]; then
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
    --version "${VERSION}" > /dev/null
fi

_jq__create_symlink
