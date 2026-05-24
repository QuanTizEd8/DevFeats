# Phase 1 skeleton — mechanically extracted from install-shell/install.bash
# Feature: install-starship
# Not yet functional. Wired up in this feature's own semantic phase.
# shellcheck shell=bash

# --- _STARSHIP_INSTALLER_URL global var (original lines 10–10) ---
_STARSHIP_INSTALLER_URL="https://starship.rs/install.sh"

# --- install_starship() + blank (original lines 200–225) ---
# ---------------------------------------------------------------------------
# install_starship — Download and run the official Starship installer.
# ---------------------------------------------------------------------------
install_starship() {
  local _bin_dir="${STARSHIP_PREFIX}/bin"

  if [ -x "${_bin_dir}/starship" ]; then
    logging__info "Starship already installed at '${_bin_dir}/starship' — skipping."
    return 0
  fi

  logging__info "Installing Starship to '${_bin_dir}'..."
  local _asset_dir
  _asset_dir="$(uri__fetch_asset "$_STARSHIP_INSTALLER_URL" --chmod-exec install.sh)"
  sh "${_asset_dir}/install.sh" --yes --bin-dir "$_bin_dir" >&2

  if [ -x "${_bin_dir}/starship" ]; then
    logging__success "Starship installed to '${_bin_dir}/starship'."
  else
    logging__error "Starship installation failed."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------

# --- Step 4: Install Starship + blank (original lines 685–691) ---
# ===================================================================
# Step 4: Install Starship
# ===================================================================
if [[ "$INSTALL_STARSHIP" == true ]]; then
  install_starship
fi

# --- configure_user preamble: vars used by the Starship blocks (from configure_user()) ---
# STARSHIP_SHELLS: keep space-joined for *zsh* / *bash* substring checks below.
local _cu_starship_shells="${STARSHIP_SHELLS[*]}"
local _cu_bin_dir="${STARSHIP_PREFIX}/bin"
local _cu_zshtheme_content=""
local _cu_bashtheme_content=""

# --- configure_user: Starship zsh hook + trailing blank (original lines 474–482) ---
# Append Starship integration for zsh.
if [[ "$_cu_starship_shells" == *zsh* ]]; then
  if ! command -v starship > /dev/null 2>&1 && [ ! -x "${_cu_bin_dir}/starship" ]; then
    logging__warn "starship_shells includes 'zsh' but starship is not on PATH — integration injected anyway."
  fi
  # shellcheck disable=SC2016
  _cu_zshtheme_content+='command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"'$'\n'
fi

# --- configure_user: Starship bash hook + trailing blank (original lines 591–599) ---
# Append Starship integration for bash.
if [[ "$_cu_starship_shells" == *bash* ]]; then
  if ! command -v starship > /dev/null 2>&1 && [ ! -x "${_cu_bin_dir}/starship" ]; then
    logging__warn "starship_shells includes 'bash' but starship is not on PATH — integration injected anyway."
  fi
  # shellcheck disable=SC2016
  _cu_bashtheme_content+='command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"'$'\n'
fi
