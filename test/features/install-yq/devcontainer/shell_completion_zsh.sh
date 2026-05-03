#!/bin/bash
# shell_completions=zsh (root):
# Verifies yq zsh completion file is written to the system-wide zsh completions directory.
set -e

source dev-container-features-test-lib

# --- yq installed ---
check "yq binary installed" command -v yq
check "yq --version succeeds" yq --version

# --- zsh completion file written to one of the expected locations ---
echo "=== /etc/zsh/completions/_yq ==="
ls -la /etc/zsh/completions/_yq 2> /dev/null || echo "(missing)"
echo "=== /usr/share/zsh/vendor-completions/_yq ==="
ls -la /usr/share/zsh/vendor-completions/_yq 2> /dev/null || echo "(missing)"
check "zsh completion file exists in system zsh completions dir" bash -c \
  'test -f /etc/zsh/completions/_yq \
  || test -f /usr/share/zsh/completions/_yq \
  || test -f /etc/completions/_yq'
check "zsh completion file is non-empty" bash -c \
  'f=""; for p in /etc/zsh/completions/_yq /usr/share/zsh/completions/_yq /etc/completions/_yq; do
    [ -f "$p" ] && f="$p" && break
  done; test -s "$f"'

reportResults
