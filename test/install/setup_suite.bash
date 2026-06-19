#!/usr/bin/env bash

setup_suite() {
  if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "⛔ bash ≥ 4.0 is required for install framework tests (found ${BASH_VERSION})" >&2
    exit 1
  fi
}

teardown_suite() { :; }
