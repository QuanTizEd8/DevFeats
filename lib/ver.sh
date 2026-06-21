# shellcheck shell=bash
# Version utilities: version string extraction, comparison, and semver validation.
#
# Provides helpers for extracting version numbers from strings, comparing
# semantic versions, and validating version tags. All functions write results
# to stdout, one item per line.

ver__cmp() {
  # @brief ver__cmp <a> <b> — Compare semantic versions per semver.org core+prerelease rules.
  #
  # Leading `v`/`V` stripped. Returns -1 if a<b, 0 if equal, 1 if a>b via exit code mapping:
  # prints -1/0/1 to stdout and returns 0 on success; returns 1 if either operand is unparseable.
  local _a="${1#v}" _b="${2#v}"
  _a="${_a#V}"
  _b="${_b#V}"
  [[ "${_a}" =~ ^[0-9]+(\.[0-9]+)*(-[^+]*)?(\+.*)?$ ]] || return 1
  [[ "${_b}" =~ ^[0-9]+(\.[0-9]+)*(-[^+]*)?(\+.*)?$ ]] || return 1
  local _core_a _core_b _pre_a _pre_b
  _core_a="${_a%%-*}"
  _core_a="${_core_a%%+*}"
  _core_b="${_b%%-*}"
  _core_b="${_core_b%%+*}"
  if [[ "${_a}" == *-* ]]; then
    _pre_a="${_a#*-}"
    _pre_a="${_pre_a%%+*}"
  else
    _pre_a=""
  fi
  if [[ "${_b}" == *-* ]]; then
    _pre_b="${_b#*-}"
    _pre_b="${_pre_b%%+*}"
  else
    _pre_b=""
  fi
  local -a _pa _pb
  IFS='.' read -ra _pa <<< "${_core_a}"
  IFS='.' read -ra _pb <<< "${_core_b}"
  local _i _max _va _vb _c=0
  _max=$((${#_pa[@]} > ${#_pb[@]} ? ${#_pa[@]} : ${#_pb[@]}))
  for ((_i = 0; _i < _max; _i++)); do
    _va="${_pa[_i]:-0}"
    _vb="${_pb[_i]:-0}"
    if ((_va > _vb)); then
      _c=1
      break
    elif ((_va < _vb)); then
      _c=-1
      break
    fi
  done
  if [[ ${_c} -ne 0 ]]; then
    printf '%s\n' "${_c}"
    return 0
  fi
  if [[ -z "${_pre_a}" && -z "${_pre_b}" ]]; then
    printf '0\n'
    return 0
  fi
  if [[ -z "${_pre_a}" ]]; then
    printf '1\n'
    return 0
  fi
  if [[ -z "${_pre_b}" ]]; then
    printf '%s\n' '-1'
    return 0
  fi
  if [[ "${_pre_a,,}" == "${_pre_b,,}" ]]; then
    printf '0\n'
    return 0
  fi
  if [[ "${_pre_a,,}" < "${_pre_b,,}" ]]; then
    printf '%s\n' '-1'
  else
    printf '%s\n' '1'
  fi
}

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
  local _cmp
  _cmp="$(ver__cmp "$1" "$2")" || return 1
  [[ "${_cmp}" -ge 0 ]]
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

ver__resolve_from_list() {
  # @brief ver__resolve_from_list <spec> — Resolve a version spec against a sorted (newest-first) list from stdin.
  #
  # Reads newline-separated version strings from stdin (newest first) and
  # resolves `<spec>` using the same logic as other version resolvers:
  #
  #   `stable` / `""`: First final (non-prerelease) version in the list.
  #   `latest`:        First version in the list (no prerelease filtering).
  #   Numeric prefix:  First final version whose bare numeric part starts with
  #                    `<spec>` (uses `ver__first_matching_prefix`). Covers both
  #                    prefix specs (e.g. `1.2` → `1.2.5`) and exact specs
  #                    (e.g. `1.2.3` → `1.2.3`).
  #
  # Pre-release status is determined by `ver__semver_is_final` on the bare
  # numeric part after stripping a leading `v`.
  #
  # Args:
  #   <spec>  Version spec: `stable`, `latest`, `""`, a numeric prefix
  #           (e.g. `5.9`), or an exact version (e.g. `5.9.1`).
  #
  # Stdin:  Newline-separated version strings, newest first.
  # Stdout: Resolved version string (exactly as it appeared on stdin).
  #
  # Returns: 0 on success, 1 if no matching version found or list is empty.
  local _spec="${1:-stable}"
  local -a _versions
  mapfile -t _versions
  ((${#_versions[@]} > 0)) || {
    logging__error "ver__resolve_from_list: version list is empty."
    return 1
  }
  case "${_spec}" in
    stable | "")
      local _v
      for _v in "${_versions[@]}"; do
        ver__semver_is_final "${_v#v}" && {
          printf '%s\n' "${_v}"
          return 0
        }
      done
      logging__error "ver__resolve_from_list: no stable release found in list."
      return 1
      ;;
    latest)
      printf '%s\n' "${_versions[0]}"
      return 0
      ;;
    *)
      local _norm
      _norm="$(ver__extract_version --keep-suffix "${_spec}" 2> /dev/null || true)"
      [[ -n "${_norm}" ]] || {
        logging__error "ver__resolve_from_list: spec '${_spec}' contains no numeric version content."
        return 1
      }
      local _v _stable_list=""
      for _v in "${_versions[@]}"; do
        ver__semver_is_final "${_v#v}" && _stable_list+="${_stable_list:+$'\n'}${_v}"
      done
      [[ -n "${_stable_list}" ]] || {
        logging__error "ver__resolve_from_list: no stable releases in list for spec '${_spec}'."
        return 1
      }
      # Exact match takes priority so that "5.9" returns "5.9" even when "5.9.1" is also in the list.
      local _exact
      _exact="$(printf '%s\n' "${_stable_list}" | awk -v s="${_norm}" '{ bare = $0; sub(/^[^0-9]*/, "", bare); if (bare == s) { print; exit } }')" || true
      if [[ -n "${_exact}" ]]; then
        printf '%s\n' "${_exact}"
        return 0
      fi
      local _matched
      _matched="$(printf '%s\n' "${_stable_list}" | ver__first_matching_prefix "${_norm}")" || {
        logging__error "ver__resolve_from_list: no version matching spec '${_spec}' found."
        return 1
      }
      printf '%s\n' "${_matched}"
      ;;
  esac
}

ver__resolve_from_sidecar() {
  # @brief ver__resolve_from_sidecar <uri> <filename_pattern> <spec> — Download a sidecar file and resolve a version spec from its embedded filenames.
  #
  # Downloads the file at `<uri>`, extracts version strings that appear in
  # filenames matching `<filename_pattern>` (which must contain `[version]`),
  # sorts them newest-first, and resolves `<spec>` via `ver__resolve_from_list`.
  #
  # For `stable`, `latest`, and `""` specs the sidecar is fetched to find the
  # current release. For any numeric spec (e.g. `5.9`, `5.9.1`) the sidecar is
  # skipped and the spec is returned as-is: the caller is expected to use the
  # exact version directly (possibly with a fallback URI for archived releases).
  # This preserves the intuitive meaning of "give me exactly version 5.9".
  #
  # Example: URI=https://www.zsh.org/pub/SHA256SUM, pattern=zsh-[version].tar.xz
  # will extract versions like `5.9.1` from lines such as:
  #   "abc123  zsh-5.9.1.tar.xz"
  #
  # Args:
  #   <uri>              URL of the sidecar file.
  #   <filename_pattern> Filename pattern with `[version]` placeholder.
  #   <spec>             Version spec: `stable`, `latest`, `""`, or an explicit
  #                      numeric version (e.g. `5.9`, `5.9.1`). Explicit numeric
  #                      specs are returned as-is without fetching the sidecar.
  #
  # Stdout: Resolved version string.
  # Returns: 0 on success, 1 on failure (download error, no versions found, no match).
  local _uri="$1" _pattern="$2" _spec="${3:-stable}"
  [[ -n "${_uri}" ]] || {
    logging__error "ver__resolve_from_sidecar: URI is required."
    return 1
  }
  [[ -n "${_pattern}" ]] || {
    logging__error "ver__resolve_from_sidecar: filename_pattern is required."
    return 1
  }
  [[ "${_pattern}" == *'[version]'* ]] || {
    logging__error "ver__resolve_from_sidecar: pattern '${_pattern}' must contain '[version]'."
    return 1
  }
  # For explicit numeric specs (not stable/latest/""), skip sidecar and return as-is.
  # This preserves the intent of e.g. "5.9" → exactly 5.9, not "latest 5.9.x".
  case "${_spec}" in
    stable | latest | "")
      ;;
    *)
      local _norm
      _norm="$(ver__extract_version --keep-suffix "${_spec}" 2> /dev/null || true)"
      [[ -n "${_norm}" ]] || {
        logging__error "ver__resolve_from_sidecar: spec '${_spec}' contains no numeric version content."
        return 1
      }
      printf '%s\n' "${_norm}"
      return 0
      ;;
  esac
  local _tmpfile
  _tmpfile="$(mktemp)" || {
    logging__error "ver__resolve_from_sidecar: failed to create temp file."
    return 1
  }
  local _fetch_rc=0
  uri__fetch_asset "${_uri}" --file-dest "${_tmpfile}" --sha256 none > /dev/null 2>&1 || _fetch_rc=$?
  if [[ ${_fetch_rc} -ne 0 ]]; then
    rm -f "${_tmpfile}"
    logging__error "ver__resolve_from_sidecar: failed to fetch '${_uri}' (rc=${_fetch_rc})."
    return 1
  fi
  local _prefix="${_pattern%%\[version\]*}"
  local _suffix="${_pattern##*\[version\]}"
  local -a _versions
  mapfile -t _versions < <(
    awk -v p="${_prefix}" -v s="${_suffix}" '
      {
        for (i = 1; i <= NF; i++) {
          w = $i
          if (p != "" && index(w, p) != 1) continue
          v = substr(w, length(p) + 1)
          if (s != "") {
            if (length(v) <= length(s)) continue
            if (substr(v, length(v) - length(s) + 1) != s) continue
            v = substr(v, 1, length(v) - length(s))
          }
          if (v ~ /^[0-9]/) print v
        }
      }
    ' "${_tmpfile}" | sort -V -r
  )
  rm -f "${_tmpfile}"
  ((${#_versions[@]} > 0)) || {
    logging__error "ver__resolve_from_sidecar: no versions found in '${_uri}' matching pattern '${_pattern}'."
    return 1
  }
  local _resolved
  _resolved="$(printf '%s\n' "${_versions[@]}" | ver__resolve_from_list "${_spec}")" || {
    logging__error "ver__resolve_from_sidecar: failed to resolve spec '${_spec}' from '${_uri}'."
    return 1
  }
  printf '%s\n' "${_resolved}"
}
