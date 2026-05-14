#!/bin/bash
# nvm_write_group=nvm, nvm_write_users=testuser:
# testuser is added to the nvm group; NVM_DIR has group-write + setgid bits
# set; and the nvm init snippet is written to the system-wide bash.bashrc.
set -e

source dev-container-features-test-lib

_NVM_DIR=/usr/local/share/nvm

# --- nvm and node installed ---
check "node on PATH" command -v node
check "nvm.sh exists" test -f "${_NVM_DIR}/nvm.sh"

# --- group created ---
echo "=== getent group nvm ==="
getent group nvm 2>&1 || echo "(not found)"
echo "=== id testuser ==="
id testuser 2>&1 || echo "(not found)"
echo "=== stat ${_NVM_DIR} ==="
stat -c "user=%U group=%G mode=%A" "${_NVM_DIR}" 2>&1 || echo "(failed)"

check "nvm group exists" bash -c 'getent group nvm >/dev/null 2>&1'

# --- testuser added to the nvm group ---
check "testuser is in nvm group" bash -c 'id -nG testuser | grep -qw nvm'

# --- directory permission bits ---
check "NVM_DIR group-owned by nvm" bash -c '[ "$(stat -c "%G" /usr/local/share/nvm)" = "nvm" ]'
check "NVM_DIR is group-writable" bash -c '[ "$(stat -c "%A" /usr/local/share/nvm | cut -c6)" = "w" ]'
check "NVM_DIR has setgid bit" bash -c 'stat -c "%A" /usr/local/share/nvm | grep -qE "^d.....(s|S)"'

# --- system-wide nvm init written to /etc/bash.bashrc ---
echo "=== /etc/bash.bashrc (nvm lines) ==="
grep "nvm" /etc/bash.bashrc 2> /dev/null || echo "(no nvm lines)"

check "/etc/bash.bashrc contains nvm.sh source" bash -c \
  'grep -Fq "nvm.sh" /etc/bash.bashrc 2>/dev/null'

reportResults
