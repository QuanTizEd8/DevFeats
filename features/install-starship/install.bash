# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# Pass --yes (non-interactive) and --bin-dir to the official Starship installer
# script, and optionally pin a version via the resolved tag.
# shellcheck disable=SC2329,SC2317
__install_run_script_pre() {
  logging__install "Preparing Starship installer args (prefix='${_RESOLVED_PREFIX}/bin')."
  declare -g -a _FEAT_INSTALL_SCRIPT_ARGS
  _FEAT_INSTALL_SCRIPT_ARGS=(--yes --bin-dir "${_RESOLVED_PREFIX}/bin")
  local _tag="${_FEAT_RESOLVED_TAG:-}"
  if [[ -z "${_tag}" && -v VERSION && -n "${VERSION}" ]]; then
    case "${VERSION}" in
      stable | latest) ;;
      *) _tag="v${VERSION}" ;;
    esac
  fi
  [[ -n "${_tag}" ]] && _FEAT_INSTALL_SCRIPT_ARGS+=(--version "${_tag}")
}

# ---------------------------------------------------------------------------
# Per-user shell activation
#
# Starship must be activated in per-user rc files (not system-wide files) so
# that the `eval "$(starship init <shell>)"` hook runs AFTER any shell
# framework config (e.g. Oh My Zsh/Oh My Bash) that sets PS1.  The
# `installsAfter` ordering guarantees that the starship block is appended
# after those frameworks' blocks when they share the same rc file.
# ---------------------------------------------------------------------------

# shellcheck disable=SC2329,SC2317
__configure_user() {
  logging__info "Writing starship init block for user '$1'."
  local _username="$1"
  local _home _group
  _home="$(users__resolve_home "$_username")"
  _group="$(users__primary_group_of "$_username" 2> /dev/null || printf '%s' "$_username")"

  logging__info "Configuring Starship for user '${_username}' (home: ${_home})..."

  local _shell _rcfile
  for _shell in "${SHELLS[@]+"${SHELLS[@]}"}"; do
    [[ -z "$_shell" ]] && continue
    case "$_shell" in
      zsh)
        if [ -n "${ZSH_RCFILE:-}" ]; then
          _rcfile="$(users__expand_path --user "$_username" "$ZSH_RCFILE")"
        else
          _rcfile="$(shell__resolve_zsh_theme_file "$_username" \
            --source-marker "install-starship-zsh-source")"
        fi
        # shellcheck disable=SC2016
        shell__write_block \
          --file "$_rcfile" \
          --marker "install-starship-zsh" \
          --content 'command -v starship > /dev/null 2>&1 && eval "$(starship init zsh)"'
        ;;
      bash)
        if [ -n "${BASH_RCFILE:-}" ]; then
          _rcfile="$(users__expand_path --user "$_username" "$BASH_RCFILE")"
        else
          _rcfile="$(shell__resolve_bash_theme_file "$_username" \
            --source-marker "install-starship-bash-source")"
        fi
        # shellcheck disable=SC2016
        shell__write_block \
          --file "$_rcfile" \
          --marker "install-starship-bash" \
          --content 'command -v starship > /dev/null 2>&1 && eval "$(starship init bash)"'
        ;;
      fish)
        shell__write_block \
          --file "${_home}/.config/fish/config.fish" \
          --marker "install-starship-fish" \
          --content 'command -q starship && starship init fish | source'
        ;;
      tcsh)
        local _tcsh_rc="${_home}/.cshrc"
        [[ -f "${_home}/.tcshrc" ]] && _tcsh_rc="${_home}/.tcshrc"
        # shellcheck disable=SC2016
        shell__write_block \
          --file "$_tcsh_rc" \
          --marker "install-starship-tcsh" \
          --content 'eval `starship init tcsh`'
        ;;
      elvish)
        shell__write_block \
          --file "${_home}/.config/elvish/rc.elv" \
          --marker "install-starship-elvish" \
          --content 'if (has-external starship) { eval (starship init elvish) }'
        ;;
      nushell)
        local _nu_init_dir="${_home}/.cache/starship"
        local _nu_env="${_home}/.config/nushell/env.nu"
        file__mkdir "$_nu_init_dir"
        # Generate the nushell init cache by running the installed binary directly.
        # The cache must be refreshed whenever starship is upgraded (re-run configure).
        "${_RESOLVED_PREFIX}/bin/starship" init nu --print-full-init \
          > "${_nu_init_dir}/init.nu" 2> /dev/null || true
        shell__write_block \
          --file "$_nu_env" \
          --marker "install-starship-nushell" \
          --content 'use ~/.cache/starship/init.nu'
        ;;
      *)
        logging__warn "Unsupported shell '${_shell}' for Starship activation — skipping."
        ;;
    esac
  done

  file__chown -R "${_username}:${_group}" "$_home" 2> /dev/null || true
  logging__success "User '${_username}' Starship configuration complete."
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  __feat_do_configure_users__
}

# Re-run per-user activation when skipping installation (if_exists=skip),
# so that adding a new shell to `shells` takes effect without reinstalling.
# shellcheck disable=SC2329,SC2317
__skip_post() {
  __feat_do_configure_users__
}

# Remove all per-user Starship activation blocks written by __configure_user.
# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  local -a _users=()
  mapfile -t _users < <(users__resolve_list)
  local _user
  for _user in "${_users[@]+"${_users[@]}"}"; do
    users__uid_of_user "${_user}" > /dev/null 2>&1 || continue
    local _home
    _home="$(users__resolve_home "${_user}")"

    local _zdotdir
    _zdotdir="$(shell__detect_zdotdir --user "${_user}" --home "${_home}")"
    local _xdg_config_home
    _xdg_config_home="$(shell__detect_xdg_config_home "${_user}")"

    # Candidate files: theme file (primary target) and rc file (source-injection target).
    # Include both ZDOTDIR and HOME paths for zsh in case ZDOTDIR differs from HOME.
    local _zsh_candidates="${_zdotdir}/zshtheme"$'\n'"${_zdotdir}/.zshrc"
    [[ "${_zdotdir}" != "${_home}" ]] && _zsh_candidates+=$'\n'"${_home}/.zshrc"

    shell__sync_block --files "$_zsh_candidates" --marker "install-starship-zsh"
    shell__sync_block --files "$_zsh_candidates" --marker "install-starship-zsh-source"
    shell__sync_block \
      --files "${_xdg_config_home}/bash/bashtheme"$'\n'"${_home}/.bashrc" \
      --marker "install-starship-bash"
    shell__sync_block --files "${_home}/.bashrc" --marker "install-starship-bash-source"
    shell__sync_block \
      --files "${_home}/.config/fish/config.fish" \
      --marker "install-starship-fish"
    shell__sync_block \
      --files "${_home}/.tcshrc"$'\n'"${_home}/.cshrc" \
      --marker "install-starship-tcsh"
    shell__sync_block \
      --files "${_home}/.config/elvish/rc.elv" \
      --marker "install-starship-elvish"
    shell__sync_block \
      --files "${_home}/.config/nushell/env.nu" \
      --marker "install-starship-nushell"
  done
}
