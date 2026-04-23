#!/usr/bin/env bats
# Unit tests for lib/graph.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib graph.sh
}

@test "graph__round_order empty edges uses priority file (higher first)" {
  h="$(mktemp "${BATS_TEST_TMPDIR}/g-h.XXXXXX")"
  s="$(mktemp "${BATS_TEST_TMPDIR}/g-s.XXXXXX")"
  p="$(mktemp "${BATS_TEST_TMPDIR}/g-p.XXXXXX")"
  : >"$h"
  : >"$s"
  printf '%s\n' "b	10" "a	0" >"$p"
  run graph__round_order --hard-edges-file "$h" --soft-edges-file "$s" --priority-file "$p" -- a b
  assert_output "b
a"
  assert_success
  rm -f "$h" "$s" "$p"
}

@test "graph__round_order respects hard edge a before b" {
  h="$(mktemp "${BATS_TEST_TMPDIR}/g-h.XXXXXX")"
  s="$(mktemp "${BATS_TEST_TMPDIR}/g-s.XXXXXX")"
  p="$(mktemp "${BATS_TEST_TMPDIR}/g-p.XXXXXX")"
  printf '%s\n' "a	b" >"$h"
  : >"$s"
  : >"$p"
  run graph__round_order --hard-edges-file "$h" --soft-edges-file "$s" --priority-file "$p" -- a b
  assert_output "a
b"
  assert_success
  rm -f "$h" "$s" "$p"
}

@test "graph__round_order fails on hard edge to unknown node" {
  h="$(mktemp "${BATS_TEST_TMPDIR}/g-h.XXXXXX")"
  s="$(mktemp "${BATS_TEST_TMPDIR}/g-s.XXXXXX")"
  p="$(mktemp "${BATS_TEST_TMPDIR}/g-p.XXXXXX")"
  printf '%s\n' "x	b" >"$h"
  : >"$s"
  : >"$p"
  run graph__round_order --hard-edges-file "$h" --soft-edges-file "$s" --priority-file "$p" -- a b
  assert_failure
  rm -f "$h" "$s" "$p"
}

@test "graph__round_order detects cycle" {
  h="$(mktemp "${BATS_TEST_TMPDIR}/g-h.XXXXXX")"
  s="$(mktemp "${BATS_TEST_TMPDIR}/g-s.XXXXXX")"
  p="$(mktemp "${BATS_TEST_TMPDIR}/g-p.XXXXXX")"
  printf '%s\n' "a	b" "b	a" >"$h"
  : >"$s"
  : >"$p"
  run graph__round_order --hard-edges-file "$h" --soft-edges-file "$s" --priority-file "$p" -- a b
  assert_failure
  rm -f "$h" "$s" "$p"
}

@test "graph__round_order orders diamond graph (a→b, a→c, b→d, c→d)" {
  h="$(mktemp "${BATS_TEST_TMPDIR}/g-h.XXXXXX")"
  s="$(mktemp "${BATS_TEST_TMPDIR}/g-s.XXXXXX")"
  p="$(mktemp "${BATS_TEST_TMPDIR}/g-p.XXXXXX")"
  printf '%s\n' "a	b" "a	c" "b	d" "c	d" >"$h"
  : >"$s"
  : >"$p"
  run graph__round_order --hard-edges-file "$h" --soft-edges-file "$s" --priority-file "$p" -- a b c d
  assert_success
  # a must come first, d must come last; b and c can appear in any order.
  [ "${lines[0]}" = "a" ]
  [ "${lines[3]}" = "d" ]
  rm -f "$h" "$s" "$p"
}

@test "graph__round_order prunes dangling soft edges (target not in node set)" {
  h="$(mktemp "${BATS_TEST_TMPDIR}/g-h.XXXXXX")"
  s="$(mktemp "${BATS_TEST_TMPDIR}/g-s.XXXXXX")"
  p="$(mktemp "${BATS_TEST_TMPDIR}/g-p.XXXXXX")"
  : >"$h"
  # x is not in the node list — the soft edge must be silently pruned.
  printf '%s\n' "x	b" >"$s"
  : >"$p"
  run graph__round_order --hard-edges-file "$h" --soft-edges-file "$s" --priority-file "$p" -- a b
  assert_success
  # Without the pruned edge, tie-break is lexicographic (alphabetical desc for
  # equal priorities uses sort -k2,2 ascending — both orders are valid, so
  # just check both nodes appear exactly once).
  [ "${#lines[@]}" -eq 2 ]
  rm -f "$h" "$s" "$p"
}

@test "graph__round_order priority tie-break within a round" {
  h="$(mktemp "${BATS_TEST_TMPDIR}/g-h.XXXXXX")"
  s="$(mktemp "${BATS_TEST_TMPDIR}/g-s.XXXXXX")"
  p="$(mktemp "${BATS_TEST_TMPDIR}/g-p.XXXXXX")"
  : >"$h"
  : >"$s"
  # Same round for a, b, c: priority decides order. Higher priority first.
  printf '%s\n' "a	5" "b	10" "c	1" >"$p"
  run graph__round_order --hard-edges-file "$h" --soft-edges-file "$s" --priority-file "$p" -- a b c
  assert_success
  [ "${lines[0]}" = "b" ]
  [ "${lines[1]}" = "a" ]
  [ "${lines[2]}" = "c" ]
  rm -f "$h" "$s" "$p"
}

@test "graph__round_order errors when called without nodes" {
  run graph__round_order --hard-edges-file /dev/null --soft-edges-file /dev/null --priority-file /dev/null --
  assert_failure
}
