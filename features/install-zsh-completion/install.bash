# Phase 1 skeleton — mechanically extracted from install-shell/install.bash
# Feature: install-zsh-completion
# Not yet functional. Wired up in this feature's own semantic phase.
# shellcheck shell=bash

# --- zsh-completions global vars (lines 2–7) (original lines 2–7) ---
_ZSH_COMPLETIONS_REPO_URL="${_GITHUB_BASE_URL}/${ZSH_COMPLETIONS_GH_REPO}"
# Shallow-clone the repo here when not using Homebrew. Completion functions live
# under src/ (see upstream README). Debian/Ubuntu .deb builds exist via OBS,
# but default apt archives do not ship this package.
_ZSH_COMPLETIONS_PREFIX="/usr/local/share/zsh-completions"
_ZSH_COMPLETIONS_SRC="${_ZSH_COMPLETIONS_PREFIX}/src"

# --- install_zsh_completions() + blank (original lines 179–199) ---
# ---------------------------------------------------------------------------
# install_zsh_completions — Extra Zsh completion definitions (zsh-users project).
# Uses Homebrew when that is the active package manager; otherwise shallow-clones
# into ${_ZSH_COMPLETIONS_PREFIX} (no apt/deb package exists for this tree).
# ---------------------------------------------------------------------------
install_zsh_completions() {
  if ospkg__os_release_match pm brew; then
    ospkg__install_user zsh-completions
    return 0
  fi

  logging__info "Installing zsh-completions (git) → '${_ZSH_COMPLETIONS_PREFIX}'..."
  git__clone --url "$_ZSH_COMPLETIONS_REPO_URL" --dir "$_ZSH_COMPLETIONS_PREFIX"
  logging__success "zsh-completions ready (fpath: '${_ZSH_COMPLETIONS_SRC}')."
  return 0
}

# Step 5.5: Wire zsh-completions fpath
# ===================================================================
# Homebrew uses share/zsh-completions. Git installs use the repo's src/
# directory (same layout as upstream manual install and OBS packages).

_zshrc_dest="${_ZSH_ETC}/zshrc"
if [ -f "$_zshrc_dest" ]; then
  _zsh_comp_fpath=""
  _brew_zc="$(brew --prefix zsh-completions 2> /dev/null)" || true
  if [ -n "$_brew_zc" ] && [ -d "${_brew_zc}/share/zsh-completions" ]; then
    _zsh_comp_fpath="${_brew_zc}/share/zsh-completions"
  elif [ -d "$_ZSH_COMPLETIONS_SRC" ]; then
    _zsh_comp_fpath="$_ZSH_COMPLETIONS_SRC"
  fi
  if [ -n "$_zsh_comp_fpath" ]; then
    shell__write_block \
      --file "$_zshrc_dest" \
      --marker "install-shell-pre-compinit" \
      --content "fpath=( '${_zsh_comp_fpath}' \${fpath[@]} )"
    logging__success "  zsh-completions fpath → ${_zshrc_dest}"
  fi
fi
