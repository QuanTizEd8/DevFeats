# shellcheck shell=bash
# String and path utilities: safe identifiers, prefix operations, version extraction.
#
# Provides helpers for safe identifier conversion, basename extraction, prefix
# stripping, and version suffix parsing. All functions write results to stdout,
# one item per line.

str__basename_each() {
  # @brief str__basename_each [<path-token>...] — For each argument, strip spaces and print basename on its own line.
  #
  # Intended for path-like tokens (e.g. `owner/repo` slugs). Built-in names
  # without `/` still pass through basename (e.g. `git` → `git`).
  #
  # Args:
  #   <path-token>...  One token per argument; pass a bash array as `"${arr[@]}"`.
  #
  # Stdout: one basename per line.
  local _tok
  for _tok in "$@"; do
    _tok="${_tok// /}"
    [ -n "$_tok" ] && basename "$_tok"
  done
  return 0
}

str__safe_id() {
  # @brief str__safe_id <s> — Convert a feature option key to an env var name: uppercase, `_` preserved, `-` → `_`.
  #
  # Args:
  #   <s>  Input string (e.g. `my-option`).
  #
  # Stdout: uppercased env var name (e.g. `MY_OPTION`).
  local s="${1-}"
  s="${s//-/_}"
  echo "${s^^}"
  return 0
}

str__has_any_prefix() {
  # @brief str__has_any_prefix <s> <prefix>... — Return 0 if `<s>` starts with any of the given prefixes.
  #
  # Args:
  #   <s>         String to test.
  #   <prefix>... One or more prefix strings to check.
  local s="${1-}"
  shift || {
    logging__error "at least one prefix is required."
    return 1
  }
  local _p
  for _p in "$@"; do
    if [[ -n "$_p" && "$s" == "$_p"* ]]; then
      return 0
    fi
  done
  return 1
}

str__strip_any_prefix() {
  # @brief str__strip_any_prefix <s> <prefix>... — Print `<s>` with the first-matching leading prefix removed; if none match, print `<s>` unchanged.
  #
  # Args:
  #   <s>         Input string.
  #   <prefix>... One or more prefix strings to try removing.
  #
  # Stdout: the modified or original string.
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

str__rsplit_once() {
  # @brief str__rsplit_once <s> <sep> — Print two lines: text before the last occurrence of `<sep>`, then text after it.
  #
  # If `<sep>` is absent from `<s>`, prints `<s>` on the first line and an empty line.
  #
  # Args:
  #   <s>    Input string.
  #   <sep>  Separator string.
  #
  # Stdout: two lines — the head and the tail.
  local s="${1-}" sep="${2-}" _head _rest _sfx
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
