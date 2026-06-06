# shellcheck shell=bash

# Prefer the Anthropic OS package repo (system-wide) when a supported package
# manager is available; fall back to npm-bundled (self-contained, no system
# Node.js required).
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  ospkg__detect 2> /dev/null || true
  case "${_OSPKG__FAMILY:-}" in
    apt | dnf | apk | brew)
      printf 'upstream-package\n'
      ;;
    *)
      printf 'npm-bundled\n'
      ;;
  esac
}

# Resolve the channel and concrete version for each install method.
#
# For npm/npm-bundled/script: resolves all version specs (channel names, semver
# prefixes, exact versions, dist-tags) via the npm registry to an exact X.Y.Z
# for reproducibility. The CDN and npm dist-tags are kept in lockstep by
# Anthropic, so a resolved version is always valid for 'claude install X.Y.Z'.
#
# For upstream-package: passes VERSION through as-is — 'stable'/'latest' are
# apt repo channel selectors, not version strings, and the apt repos only carry
# a small subset of all versions.
#
# Side-effect: sets _CLAUDE_CHANNEL ('stable' or 'latest') for use in
# __install_run_upstream_package__.
# shellcheck disable=SC2329,SC2317
__resolve_version() {
  case "${VERSION:-stable}" in
    latest) declare -g _CLAUDE_CHANNEL="latest" ;;
    *) declare -g _CLAUDE_CHANNEL="stable" ;;
  esac

  case "${METHOD:-}" in
    npm | npm-bundled | script)
      local _resolved=""
      if [[ -n "${VERSION_URI:-}" ]]; then
        _resolved="$(npm__resolve_version_uri "${VERSION_URI}" "${VERSION:-stable}" 2> /dev/null)" || _resolved=""
      fi
      printf '%s\n' "${_resolved:-${VERSION:-stable}}"
      ;;
    *)
      printf '%s\n' "${VERSION:-stable}"
      ;;
  esac
}

# upstream-package: install via the Anthropic OS package repository.
#
# Passes CHANNEL (stable/latest) and BREW_CASK to the dependency manifest for
# URL and cask-name substitution.  On apt, also passes VERSION for optional
# version pinning when a specific semver was requested; other PMs install the
# latest version from the selected channel.
# shellcheck disable=SC2329,SC2317
__install_run_upstream_package__() {
  local _channel="${_CLAUDE_CHANNEL:-stable}"
  local _pkg_version=""

  # apt supports version pinning; use it when a specific semver was requested
  # from the stable channel.
  if [[ "${_channel}" == "stable" ]]; then
    case "${VERSION:-stable}" in
      stable | latest) ;;
      *)
        ospkg__detect 2> /dev/null || true
        if [[ "${_OSPKG__FAMILY:-}" == "apt" ]]; then
          _pkg_version="${VERSION}"
        else
          logging__warn "Version pinning is only supported on apt for method=upstream-package. Installing the latest available claude-code from the '${_channel}' channel."
        fi
        ;;
    esac
  fi

  # brew uses cask names: 'claude-code' (stable) vs 'claude-code@latest' (latest).
  local _brew_cask="claude-code"
  [[ "${_channel}" == "latest" ]] && _brew_cask="claude-code@latest"

  if declare -f __install_run_upstream_package_pre > /dev/null; then
    __install_run_upstream_package_pre
  fi

  __dep_install__ run upstream-package \
    --extra-var "CHANNEL=${_channel}" \
    --extra-var "VERSION=${_pkg_version}" \
    --extra-var "BREW_CASK=${_brew_cask}"

  if declare -f __install_run_upstream_package_post > /dev/null; then
    __install_run_upstream_package_post
  fi
}

# script: pass the version string as the only argument to the bootstrap script.
# The official install.sh accepts 'stable', 'latest', or a semver string.
# shellcheck disable=SC2329,SC2317
__install_run_script_pre() {
  declare -g -a _FEAT_INSTALL_SCRIPT_ARGS
  _FEAT_INSTALL_SCRIPT_ARGS=("${VERSION:-stable}")
}

# script: when running as root, the bootstrap script installs to
# ${HOME}/.local/bin/claude (i.e. /root/.local/bin/claude).  Copy it to
# ${_RESOLVED_PREFIX}/bin/claude so it is accessible system-wide, and open the runtime
# directory so non-root users can execute the installed binary.
# shellcheck disable=SC2329,SC2317
__install_run_script_post() {
  if users__is_privileged; then
    local _src="${HOME}/.local/bin/claude"
    local _dest="${_RESOLVED_PREFIX}/bin/claude"
    if [[ -x "${_src}" && "${_src}" != "${_dest}" ]]; then
      logging__info "Copying claude from '${_src}' to '${_dest}'..."
      file__mkdir "${_RESOLVED_PREFIX}/bin"
      install -m 755 "${_src}" "${_dest}"
      local _runtime="${HOME}/.local/share/claude"
      if [[ -d "${_runtime}" ]]; then
        chmod -R a+rX "${_runtime}"
        logging__info "Made claude runtime at '${_runtime}' world-readable."
      fi
    fi
  fi
}
