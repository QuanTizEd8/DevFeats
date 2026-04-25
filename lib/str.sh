#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# Small argv / string helpers. List-style results use one stdout line per item
# (see docs/dev-guide/writing-features.md — Shared library reference).

[[ -n "${_STR__LIB_LOADED-}" ]] && return 0
_STR__LIB_LOADED=1

# @brief str__basename_each [<path-token>...] — For each argument, strip spaces and print basename on its own line.
#
# Intended for path-like tokens (e.g. `owner/repo` slugs). Built-in names
# without `/` still pass through basename (e.g. `git` → `git`).
#
# Args:
#   <path-token>  One token per argument; pass a bash array as `"${arr[@]}"`.
#
# Stdout: one basename per line.
str__basename_each() {
  local _tok
  for _tok in "$@"; do
    _tok="${_tok// /}"
    [ -n "$_tok" ] && basename "$_tok"
  done
  return 0
}

# @brief str__safe_id <s> — Validated feature option key → env var name: uppercase, preserving `_` and mapping `-` → `_`.
str__safe_id() {
  local s="${1-}"
  s="${s//-/_}"
  echo "${s^^}"
  return 0
}

# @brief str__has_any_prefix <s> <prefix>... — Return 0 if s starts with any prefix.
str__has_any_prefix() {
  local s="${1-}"
  shift || return 1
  local _p
  for _p in "$@"; do
    if [[ -n "$_p" && "$s" == "$_p"* ]]; then
      return 0
    fi
  done
  return 1
}

# @brief str__strip_any_prefix <s> <prefix>... — Print s with the first-matching leading prefix removed; if none match, print s.
str__strip_any_prefix() {
  local s="${1-}"
  shift
  local _p
  for _p in "$@"; do
    if [[ -n "$_p" && "$s" == "$_p"* ]]; then
      echo "${s#"${_p}"}"
      return 0
    fi
  done
  echo "$s"
  return 0
}

# @brief str__rsplit_once <s> <sep> — Print two lines: text before the last <sep>, then text after that separator.
str__rsplit_once() {
  local s="${1-}" sep="${2-}" _head _rest
  if [[ -z "$sep" ]]; then
    printf '%s\n' "$s"
    echo ""
    return 0
  fi
  if [[ "$s" != *"$sep"* ]]; then
    printf '%s\n' "$s"
    echo ""
    return 0
  fi
  # Avoid nested "${s%"$sep"*"}" (breaks shell quote parsing in some versions).
  _sfx="${sep}*"
  # shellcheck disable=SC2295  # unquoted intentionally — see comment above
  _head="${s%$_sfx}"
  # shellcheck disable=SC2295
  _rest="${s#$_head}"
  _rest="${_rest#"$sep"}"
  printf '%s\n' "$_head"
  printf '%s\n' "$_rest"
  return 0
}

# @brief str__extract_version_suffix <s> — If s matches … vM.m.p at the end, print M.m.p; else print empty.
str__extract_version_suffix() {
  local s="${1-}" _re
  # Avoid [[ ... ]] + literal [[:space:]] — the `]]` would terminate `[[` early.
  _re='(^|[[:space:]])v([0-9]+)\.([0-9]+)\.([0-9]+)$'
  if [[ $s =~ $_re ]]; then
    echo "${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.${BASH_REMATCH[4]}"
  else
    echo ""
  fi
  return 0
}
