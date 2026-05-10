#!/bin/bash
# Verifies that multiple users given via add_users are each configured
# with their own subuid/subgid entry and storage.conf, and that their subuid
# ranges are non-overlapping.
set -e

source dev-container-features-test-lib

_GRAPH_ROOT_BASE="/var/lib/containers/storage/users"

# --- alice configured ---
check "alice in /etc/subuid" grep -q "^alice:" /etc/subuid
check "alice in /etc/subgid" grep -q "^alice:" /etc/subgid
check "alice storage.conf exists" test -f /home/alice/.config/containers/storage.conf
check "alice storage.conf overlay driver" grep -q 'driver = "overlay"' /home/alice/.config/containers/storage.conf
check "alice storage.conf graphRoot correct" grep -qF "graphRoot = \"${_GRAPH_ROOT_BASE}/alice\"" /home/alice/.config/containers/storage.conf
check "alice home owned by alice" bash -c '[ "$(stat -c %U /home/alice)" = "alice" ]'
check "alice .config/containers owned by alice" bash -c '[ "$(stat -c %U /home/alice/.config/containers)" = "alice" ]'
check "alice .config/cni exists" test -d /home/alice/.config/cni
check "alice .config/cni owned by alice" bash -c '[ "$(stat -c %U /home/alice/.config/cni)" = "alice" ]'

# --- bob configured ---
check "bob in /etc/subuid" grep -q "^bob:" /etc/subuid
check "bob in /etc/subgid" grep -q "^bob:" /etc/subgid
check "bob storage.conf exists" test -f /home/bob/.config/containers/storage.conf
check "bob storage.conf overlay driver" grep -q 'driver = "overlay"' /home/bob/.config/containers/storage.conf
check "bob storage.conf graphRoot correct" grep -qF "graphRoot = \"${_GRAPH_ROOT_BASE}/bob\"" /home/bob/.config/containers/storage.conf
check "bob home owned by bob" bash -c '[ "$(stat -c %U /home/bob)" = "bob" ]'
check "bob .config/containers owned by bob" bash -c '[ "$(stat -c %U /home/bob/.config/containers)" = "bob" ]'
check "bob .config/cni exists" test -d /home/bob/.config/cni
check "bob .config/cni owned by bob" bash -c '[ "$(stat -c %U /home/bob/.config/cni)" = "bob" ]'

# --- subuid / subgid: disjoint 65536-id ranges (order-independent) ---
# install.bash assigns offsets in users__resolve_list order; the contract is
# non-overlapping spans, not a fixed username→offset map.
check "alice subuid count is 65536" bash -c 'grep "^alice:" /etc/subuid | cut -d: -f3 | grep -qx 65536'
check "bob subuid count is 65536" bash -c 'grep "^bob:" /etc/subuid | cut -d: -f3 | grep -qx 65536'
check "alice subuid start >= 100000" bash -c 'a=$(grep "^alice:" /etc/subuid | cut -d: -f2); test "${a}" -ge 100000'
check "bob subuid start >= 100000" bash -c 'b=$(grep "^bob:" /etc/subuid | cut -d: -f2); test "${b}" -ge 100000'
check "subuid ranges do not overlap" bash -c '
  a=$(grep "^alice:" /etc/subuid | cut -d: -f2)
  b=$(grep "^bob:" /etc/subuid | cut -d: -f2)
  d=$((a > b ? a - b : b - a))
  test "${d}" -ge 65536
'
check "alice subgid count is 65536" bash -c 'grep "^alice:" /etc/subgid | cut -d: -f3 | grep -qx 65536'
check "bob subgid count is 65536" bash -c 'grep "^bob:" /etc/subgid | cut -d: -f3 | grep -qx 65536'
check "alice subgid start >= 100000" bash -c 'a=$(grep "^alice:" /etc/subgid | cut -d: -f2); test "${a}" -ge 100000'
check "bob subgid start >= 100000" bash -c 'b=$(grep "^bob:" /etc/subgid | cut -d: -f2); test "${b}" -ge 100000'
check "subgid ranges do not overlap" bash -c '
  a=$(grep "^alice:" /etc/subgid | cut -d: -f2)
  b=$(grep "^bob:" /etc/subgid | cut -d: -f2)
  d=$((a > b ? a - b : b - a))
  test "${d}" -ge 65536
'

reportResults
