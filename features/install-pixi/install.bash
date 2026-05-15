# ── Function definitions ──────────────────────────────────────────────────────
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

_cleanup_hook() {
  logging__fn_entry "_cleanup_hook"
  if [ "${KEEP_INSTALLER:-false}" != "true" ]; then
    [ -f "${ARCHIVE:-}" ] && {
      logging__remove "Removing archive '${ARCHIVE}'"
      rm -f "${ARCHIVE}"
    }
    [ -f "${SIDECAR:-}" ] && {
      logging__remove "Removing sidecar '${SIDECAR}'"
      rm -f "${SIDECAR}"
    }
    [ -d "${INSTALLER_DIR:-}" ] && [ -z "$(ls -A "${INSTALLER_DIR:-}")" ] && {
      logging__remove "Removing empty installer directory '${INSTALLER_DIR}'"
      rmdir "${INSTALLER_DIR}"
    }
  fi
  if [[ -n "${_pixi_netrc_tmp:-}" && -f "${_pixi_netrc_tmp}" ]]; then
    logging__remove "Removing temporary netrc '${_pixi_netrc_tmp}'"
    rm -f "${_pixi_netrc_tmp}"
  fi
  logging__fn_exit "_cleanup_hook"
}

check_root_requirement() {
  logging__fn_entry "check_root_requirement"
  case "${PREFIX}" in
    /opt/* | /usr/* | /var/* | /srv/* | /snap/*)
      os__require_root
      ;;
    *)
      logging__info "Root not required for prefix '${PREFIX}'."
      ;;
  esac
  logging__fn_exit "check_root_requirement"
  return 0
}

resolve_pixi_version() {
  logging__fn_entry "resolve_pixi_version"
  if [ "${VERSION}" = "latest" ]; then
    local _tag
    _tag="$(github__latest_tag "prefix-dev/pixi")" || {
      logging__error "Failed to fetch latest pixi tag from GitHub."
      exit 1
    }
    VERSION="${_tag#v}"
    logging__info "Resolved 'latest' to version '${VERSION}'"
  else
    VERSION="${VERSION#v}"
    # Validate: must be strict semver — X.Y or X.Y.Z with only digits and dots.
    if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      logging__error "Unrecognised version string '${VERSION}'. Expected X.Y or X.Y.Z (with or without leading v)."
      exit 1
    fi
  fi
  logging__fn_exit "resolve_pixi_version"
  return 0
}

detect_triple() {
  logging__fn_entry "detect_triple"
  TRIPLE="$(os__rust_triple "${ARCH:-$(os__arch)}")" || {
    logging__error "install-pixi: unsupported platform for binary install: kernel='$(os__kernel)' arch='${ARCH:-$(os__arch)}'."
    exit 1
  }
  logging__info "Detected release triple: '${TRIPLE}'"
  logging__fn_exit "detect_triple"
  return 0
}

resolve_installer_paths() {
  logging__fn_entry "resolve_installer_paths"
  if [ -n "${DOWNLOAD_URL}" ]; then
    ARCHIVE_URL="${DOWNLOAD_URL}"
    SIDECAR_URL=""
    ARCHIVE="${INSTALLER_DIR}/pixi-custom.tar.gz"
    SIDECAR=""
    logging__info "Using custom download URL; checksum verification will be skipped."
  else
    ARCHIVE_URL="https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.tar.gz"
    SIDECAR_URL="https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.tar.gz.sha256"
    ARCHIVE="${INSTALLER_DIR}/pixi-${TRIPLE}.tar.gz"
    SIDECAR="${INSTALLER_DIR}/pixi-${TRIPLE}.tar.gz.sha256"
  fi
  logging__info "Archive URL: '${ARCHIVE_URL}'"
  logging__fn_exit "resolve_installer_paths"
  return 0
}

download_pixi() {
  logging__fn_entry "download_pixi"
  mkdir -p "${INSTALLER_DIR}"
  logging__download "Downloading pixi archive from '${ARCHIVE_URL}'"
  local _netrc_args=()
  [[ -n "${NETRC:-}" ]] && _netrc_args+=(--netrc-file "${NETRC}")
  net__fetch_url_file "${ARCHIVE_URL}" "${ARCHIVE}" "${_netrc_args[@]}"
  if [ -n "${SIDECAR_URL:-}" ]; then
    logging__download "Downloading checksum sidecar from '${SIDECAR_URL}'"
    net__fetch_url_file "${SIDECAR_URL}" "${SIDECAR}" "${_netrc_args[@]}"
  fi
  logging__fn_exit "download_pixi"
}

verify_pixi() {
  logging__fn_entry "verify_pixi"
  if [ -z "${SIDECAR_URL:-}" ]; then
    logging__warn "Checksum verification skipped (custom download_url set; ensure your source is trusted)."
    logging__fn_exit "verify_pixi"
    return 0
  fi
  logging__inspect "Verifying SHA-256 checksum..."
  verify__sha_sidecar "${ARCHIVE}" "${SIDECAR}"
  logging__success "Checksum verified."
  logging__fn_exit "verify_pixi"
  return 0
}

# get_installed_version — prints bare semver (no v prefix) to stdout, or empty string.
get_installed_version() {
  local _bin="${PREFIX}/bin/pixi"
  if [ -x "${_bin}" ]; then
    "${_bin}" --version 2> /dev/null | awk '{print $NF}' | sed 's/^v//' || true
    return 0
  fi
  if command -v pixi > /dev/null 2>&1; then
    pixi --version 2> /dev/null | awk '{print $NF}' | sed 's/^v//' || true
    return 0
  fi
  echo ""
  return 0
}

handle_if_exists() {
  logging__fn_entry "handle_if_exists"
  case "${IF_EXISTS}" in
    skip)
      logging__info "pixi already installed — skipping install (if_exists=skip)."
      _SKIP_INSTALL=true
      ;;
    fail)
      logging__error "pixi already installed and if_exists=fail."
      exit 1
      ;;
    reinstall)
      logging__remove "Removing existing pixi binary at '${PREFIX}/bin/pixi'..."
      rm -f "${PREFIX}/bin/pixi"
      _SKIP_INSTALL=false
      ;;
    update)
      update_pixi
      _SKIP_INSTALL=true
      ;;
  esac
  logging__fn_exit "handle_if_exists"
  return 0
}

update_pixi() {
  logging__fn_entry "update_pixi"
  local _pixi_bin
  if [ -x "${PREFIX}/bin/pixi" ]; then
    _pixi_bin="${PREFIX}/bin/pixi"
  elif command -v pixi > /dev/null 2>&1; then
    _pixi_bin="$(command -v pixi)"
  else
    logging__error "Cannot find pixi binary for self-update."
    exit 1
  fi
  logging__info "Updating pixi via self-update to version '${VERSION}'..."
  "${_pixi_bin}" self-update --version "${VERSION}"
  logging__fn_exit "update_pixi"
  return 0
}

install_pixi_binary() {
  logging__fn_entry "install_pixi_binary"
  local _tmpdir="${INSTALLER_DIR}/_extract"
  mkdir -p "${PREFIX}/bin" "${_tmpdir}"
  logging__install "Extracting archive to '${PREFIX}/bin/pixi'..."
  file__extract_archive "${ARCHIVE}" "${_tmpdir}"
  mv "${_tmpdir}/pixi" "${PREFIX}/bin/pixi"
  chmod 0755 "${PREFIX}/bin/pixi"
  rm -rf "${_tmpdir}"
  logging__success "pixi binary installed to '${PREFIX}/bin/pixi'"
  logging__fn_exit "install_pixi_binary"
  return 0
}

verify_installed_binary() {
  logging__fn_entry "verify_installed_binary"
  local _ver=""
  if "${PREFIX}/bin/pixi" --version > /dev/null 2>&1; then
    _ver="$("${PREFIX}/bin/pixi" --version 2> /dev/null)"
  elif command -v pixi > /dev/null 2>&1; then
    _ver="$(pixi --version 2> /dev/null)"
  else
    logging__error "pixi not found at '${PREFIX}/bin/pixi' and not on PATH."
    exit 1
  fi
  logging__info "Verified pixi: ${_ver}"
  logging__fn_exit "verify_installed_binary"
  return 0
}

prefix_activation_snippet() {
  if [ -n "${HOME_DIR}" ]; then
    printf 'export PIXI_HOME="%s"\n' "${HOME_DIR}"
  else
    # shellcheck disable=SC2016
    printf 'export PIXI_HOME="${HOME}/.pixi"\n'
  fi
  return 0
}

_prefix_post_install() {
  _prefix_post_install__generated
  if os__is_devcontainer_build; then
    printf '#!/bin/sh\n"%s" info --extended\n' "${_DF_EXPECTED_CMD}" \
      > "${_FEAT_SHARE_DIR}/lifecycle--on-create--verification.sh"
    chmod +x "${_FEAT_SHARE_DIR}/lifecycle--on-create--verification.sh"
  fi
}

install_completion() {
  logging__fn_entry "install_completion"
  if [ "${#SHELL_COMPLETIONS[@]}" -eq 0 ]; then
    logging__info "shell_completions is empty; skipping completion install."
    logging__fn_exit "install_completion"
    return 0
  fi
  local _marker="pixi completion (install-pixi)"
  local _shell
  for _shell in "${SHELL_COMPLETIONS[@]}"; do
    local _content="eval \"\$(pixi completion --shell ${_shell})\""
    local _target_file
    case "${_shell}" in
      bash)
        if users__is_root; then
          _target_file="$(shell__detect_bashrc)"
        else
          _target_file="${HOME}/.bashrc"
        fi
        ;;
      zsh)
        if users__is_root; then
          _target_file="$(shell__detect_zshdir)/zshenv"
        else
          _target_file="${HOME}/.zshenv"
        fi
        ;;
      fish)
        _target_file="${HOME}/.config/fish/config.fish"
        ;;
      nushell)
        _target_file="${HOME}/.config/nushell/config.nu"
        ;;
      elvish)
        _target_file="${HOME}/.config/elvish/rc.elv"
        ;;
      *)
        logging__error "Unsupported shell: '${_shell}' (expected: bash, zsh, fish, nushell, elvish)"
        exit 1
        ;;
    esac
    mkdir -p "$(dirname "${_target_file}")"
    [ -f "${_target_file}" ] || touch "${_target_file}"
    shell__write_block --file "${_target_file}" --marker "${_marker}" --content "${_content}"
    logging__success "Shell completion for '${_shell}' written to '${_target_file}'"
  done
  logging__fn_exit "install_completion"
  return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

# shellcheck source=lib/os.sh
. "${_BASE_DIR}/_lib/os.sh"
# shellcheck source=lib/shell.sh
. "${_BASE_DIR}/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "${_BASE_DIR}/_lib/github.sh"
# shellcheck source=lib/verify.sh
. "${_BASE_DIR}/_lib/verify.sh"
# shellcheck source=lib/uri.sh
# shellcheck disable=SC1094
. "${_BASE_DIR}/_lib/uri.sh"
# shellcheck source=lib/file.sh
. "${_BASE_DIR}/_lib/file.sh"
# shellcheck source=lib/install/common.sh
. "${_BASE_DIR}/_lib/install/common.sh"

declare -p FETCH_HEADERS &> /dev/null || FETCH_HEADERS=()
[ "${FETCH_NETRC+defined}" ] || FETCH_NETRC=""

_pixi_uri_fetch_args=()
if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
  for _ph in "${FETCH_HEADERS[@]}"; do
    [[ -n "${_ph}" ]] && _pixi_uri_fetch_args+=(--header "$_ph")
  done
fi
[[ -n "${FETCH_NETRC:-}" ]] && _pixi_uri_fetch_args+=(--netrc-file "${FETCH_NETRC}")

if [[ -n "${NETRC:-}" ]]; then
  case "${NETRC}" in
    http://* | https://* | file://* | oci://* | gh://*)
      _pixi_netrc_tmp="$(mktemp "${TMPDIR:-/tmp}/devfeats-netrc.XXXXXX")"
      chmod 600 "${_pixi_netrc_tmp}" || true
      NETRC="$(uri__resolve "${NETRC}" "${_pixi_netrc_tmp}" "${_pixi_uri_fetch_args[@]}")"
      chmod 600 "${NETRC}"
      ;;
  esac
fi

check_root_requirement
resolve_pixi_version

# Version-match idempotency check: only compare against the requested install
# target (PREFIX/bin/pixi).  A pixi reachable only via PATH at a different location
# does NOT satisfy the target — we still need to install there.
_INSTALLED_VER=""
if [ -x "${PREFIX}/bin/pixi" ]; then
  _INSTALLED_VER="$(get_installed_version)"
fi
_SKIP_INSTALL=false
if [ -n "${_INSTALLED_VER}" ] && [ "${_INSTALLED_VER}" = "${VERSION}" ]; then
  logging__info "Installed pixi version '${_INSTALLED_VER}' matches '${VERSION}'. Skipping install."
  _SKIP_INSTALL=true
elif [ -x "${PREFIX}/bin/pixi" ]; then
  # A different version is already at the requested install target: apply policy.
  handle_if_exists
fi

if [ "${_SKIP_INSTALL}" != "true" ]; then
  detect_triple
  resolve_installer_paths
  download_pixi
  verify_pixi
  install_pixi_binary
fi

verify_installed_binary
install_completion

# ---------------------------------------------------------------------------
# Devcontainer entrypoint
#
# In a devcontainer build, install a root-owned entrypoint that runs at
# container start to fix ownership of the .pixi named volume mount.
# Docker creates named volumes owned by root; the entrypoint chowns the
# directory to the configured remote user so they can write to it.
# On standalone/host installs there is no named volume and no entrypoint
# caller, so this section is skipped.
# ---------------------------------------------------------------------------
if os__is_devcontainer_build; then
  _ENTRYPOINT_DEST="${_FEAT_SHARE_DIR}/entrypoint.sh"
  install__copy_bin "${_FILES_DIR}/entrypoint.sh" "$_ENTRYPOINT_DEST"
  printf 'PIXI_VOLUME_USER="%s"\n' "${_REMOTE_USER}" \
    > "${_FEAT_SHARE_DIR}/entrypoint.sh.conf"
fi
