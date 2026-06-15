#!/bin/sh

install_plugins() {
  _plugins_file="${0}.plugins"
  [ -f "$_plugins_file" ] || return 0
  while IFS= read -r _plugin; do
    [ -z "$_plugin" ] && continue
    printf '[install-copilot] Installing Copilot plugin: %s\n' "$_plugin" >&2
    copilot plugin install "$_plugin" || warn "Failed to install Copilot plugin '${_plugin}' (non-fatal)."
  done < "$_plugins_file"
}
install_plugins
