#!/bin/bash
# method=source, version=stable: full source build from kernel.org tarball.
# Verifies source-specific artifacts that package installs do not create.
set -e

source dev-container-features-test-lib

# --- binary at default prefix ---
check "git at /usr/local/bin/git" test -f /usr/local/bin/git
check "git binary is executable" test -x /usr/local/bin/git
check "command -v resolves to /usr/local/bin/git" bash -c '[ "$(command -v git)" = "/usr/local/bin/git" ]'
echo "=== git --version ==="
/usr/local/bin/git --version 2>&1 || echo "(failed)"
check "git --version succeeds" /usr/local/bin/git --version
check "git version is at least 2" bash -c '[ "$(/usr/local/bin/git --version | awk "{print \$3}" | cut -d. -f1)" -ge 2 ]'

# --- no apt source list created (source build, no PPA) ---
check "no PPA sources.list entry" bash -c '! test -f /etc/apt/sources.list.d/git-core-ppa.list'

# --- system gitconfig (default_branch=main default) ---
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

# --- PATH export (export_path=auto default, prefix=/usr/local) ---
# The export_path_main() guard skips all PATH writes when prefix is /usr/local
# because it is already on PATH in every container image.
echo "=== /etc/profile.d/${_EXPORT_PROFILE_D} ==="
cat "/etc/profile.d/${_EXPORT_PROFILE_D}" 2> /dev/null || echo "(missing — expected)"
check "profile.d script NOT written (default prefix already on PATH)" bash -c '! test -f "/etc/profile.d/${_EXPORT_PROFILE_D}"'
check "bashrc PATH block NOT written" bash -c '! grep -Fq "git PATH (install-git)" /etc/bash.bashrc 2>/dev/null'
check "zshenv PATH block NOT written" bash -c '! grep -Fq "git PATH (install-git)" /etc/zsh/zshenv 2>/dev/null'

# --- shell completions (shell_completions="bash zsh" default) ---
check "bash completion installed" test -f /etc/bash_completion.d/git
check "zsh completion installed in detected zshdir" test -f /etc/zsh/completions/_git

reportResults
