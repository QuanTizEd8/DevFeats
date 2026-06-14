# ~/.bash_profile: executed by bash (and zsh via ~/.zprofile) for login shells.
#
# Sources ~/.shellenv for environment variables, then ~/.bashrc for interactive
# bash config.  The ~/.bashrc source is guarded by $BASH so that when zsh
# sources this file via 'emulate sh', bash-specific files are not loaded.
# >>> setup-shell-bash-profile-shellenv >>>
[ -f "$HOME/.shellenv" ] && . "$HOME/.shellenv"
# <<< setup-shell-bash-profile-shellenv <<<

if [ "${BASH-}" ] && [ "$BASH" != "/bin/sh" ]; then
    [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
fi
