# shellcheck shell=bash
# Version utilities: version string extraction, comparison, and semver validation.
#
# Provides helpers for extracting version numbers from strings, comparing
# semantic versions, and validating version tags. All functions write results
# to stdout, one item per line.

ver__semver_ge() {
  # @brief ver__semver_ge <a> <b> — Return 0 if semantic version `a` is greater than or equal to `b`.
  #
  # Leading `v` is stripped from both arguments before comparison. Comparison
  # uses `sort -V` (GNU coreutils version sort), which handles multi-component
  # semver strings (e.g. `1.10.0` vs `1.9.0`) correctly.
  #
  # Args:
  #   <a>  First version string (e.g. `1.2.3` or `v1.2.3`).
  #   <b>  Second version string to compare against.
  #
  # Returns: 0 if a >= b, 1 if a < b.
  local _a="${1#v}" _b="${2#v}"
  [[ "$_a" == "$_b" ]] && return 0
  [[ "$(printf '%s\n' "$_a" "$_b" | sort -V | tail -n1)" == "$_a" ]]
}

ver__semver_is_final() {
  # @brief ver__semver_is_final <version> — Return 0 if the version string is a final release.
  #
  # A version is considered final if the numeric core (one or more integers
  # separated by dots, e.g. `1`, `1.2`, `1.2.3`, `1.2.3.4`) is optionally
  # followed by a `+` build-metadata suffix.  Any pre-release component
  # (separated by `-`) makes the version non-final:
  #
  #   Final:     `1.2.3`, `1`, `1.2.3.4`, `1.2.3+build.1`, `1.2.3+20230101`
  #   Non-final: `1.2.3-rc1`, `1.0.0-beta.1`, `1.2.3-rc1+build`, `3.13.0a4`
  #
  # Build-metadata identifiers follow the semver spec: ASCII alphanumerics and
  # hyphens only (`[0-9A-Za-z-]`), dot-separated.
  #
  # Args:
  #   <version>  Bare version string (leading `v` is NOT stripped).
  #
  # Returns: 0 if final, 1 otherwise.
  [[ "${1-}" =~ ^[0-9]+(\.[0-9]+)*(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]
}

ver__extract_version() {
  # @brief ver__extract_version [--keep-suffix] [--full-match] <s> — Extract the first version number from a string.
  #
  # Supports major-only (X), two-part (X.Y), and full semver (X.Y.Z...) formats.
  # In default (text-scanning) mode the function first looks for a dot-separated
  # match (X.Y or longer), which avoids false positives on isolated integers in
  # prose; it falls back to a single-digit match only when no dot-separated
  # version is found.
  #
  # --keep-suffix  Also capture inline labels and separator-based suffixes
  #                (e.g. `a4`, `rc1`, `-rc1`, `.post1`, `+build.1`, `~beta1`):
  #                  "v1.2.3-rc1"  → "1.2.3-rc1"
  #                  "3.13.0a4"    → "3.13.0a4"
  #                  "1.2.3.post1" → "1.2.3.post1"
  #
  # --full-match   Require the entire input (after stripping a leading `v`) to
  #                match the version pattern instead of scanning for a substring.
  #                Rejects strings where a version is merely embedded in a
  #                non-version string:
  #                  "jq-1.7.1"   → ""          (package-name prefix: rejected)
  #                  "arm64-1.0.0"→ ""          (non-numeric prefix: rejected)
  #                  "v1.2.3"     → "1.2.3"
  #                  "v1"         → "1"          (major-only spec accepted)
  #
  # Both flags are independent and may be combined:
  #   ver__extract_version --full-match --keep-suffix "v1.2.3-rc1" → "1.2.3-rc1"
  #   ver__extract_version --full-match --keep-suffix "v1"         → "1"
  #   ver__extract_version --full-match --keep-suffix "arm64-1.0.0" → ""
  #
  # Common input formats (default mode):
  #   "jq-1.7.1"               → "1.7.1"
  #   "v3.7.0"                 → "3.7.0"
  #   "gh version 2.46.0 ..."  → "2.46.0"
  #   "node v20.11.0"          → "20.11.0"
  #   "git version 2.44.0"     → "2.44.0"
  #   "1"                      → "1"          (major-only)
  #
  # Always returns 0; empty stdout signals no match.
  #
  # Args:
  #   [--keep-suffix]  Preserve pre-release/build suffix in output.
  #   [--full-match]   Require full-string match (after stripping leading `v`).
  #   <s>              Input string.
  #
  # Stdout: version string, or empty if none found.
  local _keep_suffix=false _full_match=false _input=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-suffix) _keep_suffix=true ;;
      --full-match) _full_match=true ;;
      *) _input="$1" ;;
    esac
    shift
  done

  if [[ "$_full_match" == true ]]; then
    local _s="${_input#v}" _re
    _re='^[0-9]+(\.[0-9]+)*([a-zA-Z][a-zA-Z0-9]*)?([._+~-][0-9A-Za-z]+)*$'
    if [[ "$_s" =~ $_re ]]; then
      if [[ "$_keep_suffix" == true ]]; then
        printf '%s\n' "$_s"
      else
        local _v
        _v="$(printf '%s\n' "$_s" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*' | head -1 || true)"
        [[ -z "$_v" ]] && _v="$(printf '%s\n' "$_s" | grep -oE '[0-9]+' | head -1 || true)"
        [[ -n "$_v" ]] && printf '%s\n' "$_v" || true
      fi
    fi
    return 0
  fi

  local _v
  if [[ "$_keep_suffix" == true ]]; then
    _v="$(printf '%s\n' "$_input" |
      grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*([a-zA-Z][a-zA-Z0-9]*)?([._+~-][0-9A-Za-z]+)*' |
      head -1 || true)"
    if [[ -z "$_v" ]]; then
      _v="$(printf '%s\n' "$_input" |
        grep -oE '[0-9]+([a-zA-Z][a-zA-Z0-9]*)?([._+~-][0-9A-Za-z]+)*' |
        head -1 || true)"
    fi
  else
    _v="$(printf '%s\n' "$_input" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*' | head -1 || true)"
    [[ -z "$_v" ]] && _v="$(printf '%s\n' "$_input" | grep -oE '[0-9]+' | head -1 || true)"
  fi
  [[ -n "$_v" ]] && printf '%s\n' "$_v" || true
}

ver__first_matching_prefix() {
  # @brief ver__first_matching_prefix <spec> — Print the first line from stdin whose bare version matches <spec> as a prefix.
  #
  # Reads newline-separated version strings from stdin (one per line). Strips
  # any leading non-numeric characters from each line before comparing, so
  # tagged versions like `v1.2.3` or `jq-1.7.1` are handled transparently.
  # A line matches when its bare numeric part equals `<spec>` exactly, or when
  # it starts with `<spec>` followed immediately by `.` or `-` (e.g. spec
  # `1.2` matches `1.2.3` and `1.2.0-rc1` but not `1.20.0`).
  #
  # Args:
  #   <spec>  Normalised version prefix to match (e.g. `1`, `1.2`, `1.2.3`).
  #           Must contain only digits and dots (no leading non-numeric prefix).
  #
  # Stdin:  Newline-separated list of version strings to scan (newest first).
  # Stdout: First matching line from stdin, unchanged.
  #
  # Returns: 0 on match, 1 if no line matches.
  local _spec="$1"
  local _result
  _result="$(awk -v s="$_spec" '
    {
      bare = $0; sub(/^[^0-9]*/, "", bare)
      c = substr(bare, length(s) + 1, 1)
      if (bare == s || (index(bare, s) == 1 && (c == "." || c == "-"))) { print; exit }
    }')" || true
  [ -n "$_result" ] || {
    logging__error "no version matched prefix '${_spec}'."
    return 1
  }
  printf '%s\n' "$_result"
}
