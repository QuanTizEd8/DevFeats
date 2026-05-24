# Phase 1 skeleton — mechanically extracted from install-shell/install.bash
# Feature: install-fzf
# Not yet functional. Wired up in this feature's own semantic phase.
# shellcheck shell=bash

# --- install_fzf() + blank (original lines 128–178) ---
# ---------------------------------------------------------------------------
# install_fzf — Download fzf from GitHub Releases, verify checksum, install.
# Uses: FZF_PREFIX.
# ---------------------------------------------------------------------------
install_fzf() {
  local _bin_dir="${FZF_PREFIX}/bin"

  if [ -x "${_bin_dir}/fzf" ]; then
    logging__info "fzf already installed at '${_bin_dir}/fzf' — skipping."
    return 0
  fi

  local _out _version
  _out="$(github__resolve_version "${FZF_GH_REPO}" "")" || {
    logging__error "Failed to resolve fzf version from GitHub."
    return 1
  }
  _version="${_out#*$'\n'}"
  logging__info "Installing fzf ${_version} to '${_bin_dir}'..."

  local _os _fzf_arch
  _os="$(os__release_kernel)" || {
    logging__error "Unsupported kernel for fzf install: '$(os__kernel)'"
    return 1
  }
  _fzf_arch="$(os__release_arch)" || {
    logging__error "Unsupported arch for fzf install: '$(os__arch)'"
    return 1
  }
  case "$_fzf_arch" in
    amd64 | arm64) ;;
    *)
      logging__error "Unsupported arch for fzf install: '$(os__arch)'"
      return 1
      ;;
  esac

  local _filename="fzf-${_version}-${_os}_${_fzf_arch}.tar.gz"
  local _base_url="${_GITHUB_BASE_URL}/${FZF_GH_REPO}/releases/download/v${_version}"

  github__install_release \
    --repo "${FZF_GH_REPO}" --tag "v${_version}" \
    --asset "$_filename" --binary-src fzf --binary-dest "${_bin_dir}/" \
    --sidecar "${_base_url}/fzf_${_version}_checksums.txt" \
    --installer-dir "${INSTALLER_DIR}" ||
    return 1

  logging__success "fzf installed to '${_bin_dir}/fzf'."
  return 0
}

# --- fzf sub-block of Step 2.5 + blank (original lines 659–662) ---
if [[ "$INSTALL_FZF" == true ]]; then
  install_fzf
fi

# --- configure_user preamble: vars used by the fzf blocks (from configure_user()) ---
local _cu_zshtheme_content=""
local _cu_bashtheme_content=""

# --- configure_user: fzf zsh hook + trailing blank (original lines 468–473) ---
# Append fzf key-bindings and completion for zsh.
if [[ "$INSTALL_FZF" == true ]]; then
  # shellcheck disable=SC2016
  _cu_zshtheme_content+='command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"'$'\n'
fi

# --- configure_user: fzf bash hook + trailing blank (original lines 585–590) ---
# Append fzf key-bindings and completion for bash.
if [[ "$INSTALL_FZF" == true ]]; then
  # shellcheck disable=SC2016
  _cu_bashtheme_content+='command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"'$'\n'
fi
