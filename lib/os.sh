# shellcheck shell=bash
# OS and hardware detection: cached accessors for kernel, arch, distro ID, and platform tag.
#
# Results for `os__kernel` and `os__arch` are cached for the lifetime of the
# script. `os__platform` maps OS IDs to a canonical tag (`debian`, `alpine`,
# `rhel`, `suse`, `macos`).

# ── Cached globals (populated lazily) ────────────────────────────────────────
_OS__KERNEL=""
_OS__ARCH=""
_OS__ID=""
_OS__ID_LIKE=""
_OS__CODENAME=""
_OS__PLATFORM=""
_OS__RELEASE_LOADED=""

# @brief os__kernel — Print the kernel name (`Linux` or `Darwin`). Cached; use instead of `uname -s`.
#
# Stdout: kernel name.
os__kernel() {
  [ -n "${_OS__KERNEL-}" ] || _OS__KERNEL="$(uname -s)"
  echo "$_OS__KERNEL"
  return 0
}

# @brief os__arch — Print the CPU architecture (e.g. `x86_64`, `aarch64`). Cached; use instead of `uname -m`.
#
# Stdout: architecture string.
os__arch() {
  [ -n "${_OS__ARCH-}" ] || _OS__ARCH="$(uname -m)"
  echo "$_OS__ARCH"
  return 0
}

# @brief os__id — Print the `ID` field from `/etc/os-release` (e.g. `ubuntu`, `alpine`).
#
# Stdout: distro ID string, or empty on macOS.
os__id() {
  _os__load_release
  echo "${_OS__ID:-}"
  return 0
}

# @brief os__id_like — Print the `ID_LIKE` field from `/etc/os-release` (space-separated distro family list).
#
# Stdout: distro family string, or empty if absent.
os__id_like() {
  _os__load_release
  echo "${_OS__ID_LIKE:-}"
  return 0
}

# @brief os__platform — Print a canonical platform tag: `debian` | `alpine` | `rhel` | `suse` | `macos`.
#
# Falls back to `debian` for unrecognised Linux distros.
#
# Stdout: one of `debian`, `alpine`, `rhel`, `suse`, `macos`.
os__platform() {
  if [ -n "${_OS__PLATFORM-}" ]; then
    echo "$_OS__PLATFORM"
    return 0
  fi
  _os__load_release
  case "${_OS__ID:-}" in
    debian | ubuntu) _OS__PLATFORM="debian" ;;
    alpine) _OS__PLATFORM="alpine" ;;
    rhel | centos | fedora | rocky | almalinux) _OS__PLATFORM="rhel" ;;
    opensuse-leap | opensuse-tumbleweed | opensuse | sles | sle-micro) _OS__PLATFORM="suse" ;;
    *)
      case "${_OS__ID_LIKE:-}" in
        *debian* | *ubuntu*) _OS__PLATFORM="debian" ;;
        *alpine*) _OS__PLATFORM="alpine" ;;
        *rhel* | *fedora* | *centos* | *"Red Hat"*) _OS__PLATFORM="rhel" ;;
        *suse*) _OS__PLATFORM="suse" ;;
        *)
          [ "$(uname -s)" = "Darwin" ] && _OS__PLATFORM="macos" || _OS__PLATFORM="debian"
          ;;
      esac
      ;;
  esac
  echo "$_OS__PLATFORM"
  return 0
}

# @brief os__release_kernel [<flavor>] — Print the kernel identifier used in release asset filenames.
#
# Maps the result of `os__kernel` to the token used by release asset naming
# conventions. Returns 1 with a logged error for unsupported kernels or flavors.
#
# Flavor `github` (default): `linux` or `darwin` — standard GitHub releases.
# Flavor `gh`:               `linux` or `macOS`  — GitHub CLI asset naming.
# Flavor `macos`:            `linux` or `macos`  — tools that use "macos" for Darwin (e.g. jq ≥1.7).
# Flavor `osx`:              `linux` or `osx`    — tools that use "osx" for Darwin (e.g. jq <1.7).
#
# Stdout: kernel token string.
# Returns: 0 on success, 1 if the kernel or flavor is unsupported.
os__release_kernel() {
  local _flavor="${1:-github}"
  case "$(os__kernel)" in
    Linux) printf 'linux\n' ;;
    Darwin)
      case "$_flavor" in
        github) printf 'darwin\n' ;;
        gh) printf 'macOS\n' ;;
        macos) printf 'macos\n' ;;
        osx) printf 'osx\n' ;;
        *)
          logging__error "unknown flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    *)
      logging__error "unsupported kernel '$(os__kernel)'."
      return 1
      ;;
  esac
}

# @brief os__release_arch [<raw-arch>] [--flavor <token>] — Map a raw architecture string to a release asset token.
#
# Accepts raw `uname -m` output or already-normalised values. Defaults to
# `os__arch` when omitted. Pass an explicit value when a user-supplied arch
# override is in play (e.g. the $ARCH option in install-node).
#
# Flavor `github` (default): amd64, arm64, armv7, i386, ppc64le, s390x, riscv64, loong64.
# Flavor `node`:             x64,  arm64, armv7l, ppc64le, s390x.
# Flavor `gh`:               amd64, arm64, armv6, 386.
# Flavor `bitness`:          64 (64-bit arches) or 32 (32-bit arches).
#
# Returns: 0 on success, 1 if the arch/flavor combination is unsupported.
# shellcheck disable=SC2120
os__release_arch() {
  local _raw="" _flavor="github"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --flavor)
        shift
        _flavor="${1-}"
        ;;
      *) _raw="$1" ;;
    esac
    shift
  done
  [[ -n "$_raw" ]] || _raw="$(os__arch)"
  case "$_raw" in
    x86_64 | amd64 | x64)
      case "$_flavor" in
        github | gh) printf 'amd64\n' ;;
        node) printf 'x64\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "unknown flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    aarch64 | arm64)
      case "$_flavor" in
        bitness) printf '64\n' ;;
        *) printf 'arm64\n' ;;
      esac
      ;;
    armv7l | armv7)
      case "$_flavor" in
        github) printf 'armv7\n' ;;
        node) printf 'armv7l\n' ;;
        gh) printf 'armv6\n' ;;
        bitness) printf '32\n' ;;
        *)
          logging__error "unknown flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    armv6l)
      case "$_flavor" in
        gh) printf 'armv6\n' ;;
        bitness) printf '32\n' ;;
        *)
          logging__error "architecture 'armv6l' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    i386 | i686)
      case "$_flavor" in
        github) printf 'i386\n' ;;
        gh) printf '386\n' ;;
        bitness) printf '32\n' ;;
        *)
          logging__error "architecture '${_raw}' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    ppc64le)
      case "$_flavor" in
        github | node) printf 'ppc64le\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 'ppc64le' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    s390x)
      case "$_flavor" in
        github | node) printf 's390x\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 's390x' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    riscv64)
      case "$_flavor" in
        github) printf 'riscv64\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 'riscv64' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    loong64 | loongarch64)
      case "$_flavor" in
        github) printf 'loong64\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 'loong64' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    *)
      logging__error "unsupported architecture '${_raw}'."
      return 1
      ;;
  esac
}

# @brief os__rust_triple [<raw-arch>] — Print the Rust target triple for the current kernel and architecture.
#
# Accepts an optional raw architecture string (uname -m output or a user-supplied
# override). Defaults to os__arch. The Linux env suffix (musl/gnu) is
# arch-determined: riscv64 must use gnu (no musl target exists); all others use musl.
#
# Stdout: Rust target triple (e.g. x86_64-unknown-linux-musl, aarch64-apple-darwin).
# Returns: 0 on success, 1 if the kernel/arch combination is unsupported.
os__rust_triple() {
  local _raw="${1:-$(os__arch)}"
  case "$(os__kernel):${_raw}" in
    Linux:x86_64 | Linux:amd64) printf 'x86_64-unknown-linux-musl\n' ;;
    Linux:aarch64 | Linux:arm64) printf 'aarch64-unknown-linux-musl\n' ;;
    Linux:riscv64) printf 'riscv64gc-unknown-linux-gnu\n' ;;
    Darwin:x86_64 | Darwin:amd64) printf 'x86_64-apple-darwin\n' ;;
    Darwin:aarch64 | Darwin:arm64) printf 'aarch64-apple-darwin\n' ;;
    *)
      logging__error "unsupported kernel/arch '$(os__kernel)/${_raw}'."
      return 1
      ;;
  esac
}

# @brief os__font_dir — Print the platform-appropriate font directory for the current installation scope.
#
# Stdout: `/usr/share/fonts` (root/system), `~/Library/Fonts` (macOS non-root), or `${XDG_DATA_HOME:-~/.local/share}/fonts` (Linux non-root).
os__font_dir() {
  if users__is_root; then
    echo "/usr/share/fonts"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    echo "${HOME}/Library/Fonts"
  else
    echo "${XDG_DATA_HOME:-${HOME}/.local/share}/fonts"
  fi
  return 0
}

# @brief os__is_devcontainer_build — Return 0 when this script is being executed as a devcontainer feature installer, 1 otherwise.
#
# The devcontainer Feature spec mandates that ALL FOUR of the following
# variables be present in the installer environment, regardless of which
# spec-compliant tool performs the build:
#
#   _REMOTE_USER         remoteUser from devcontainer.json
#   _CONTAINER_USER      containerUser (or default container user)
#   _REMOTE_USER_HOME    home directory of _REMOTE_USER
#   _CONTAINER_USER_HOME home directory of _CONTAINER_USER
#
# Requiring all four together is the spec-defined signal:
# - `_REMOTE_USER` alone may be set by other tools (e.g. SysSet).
# - `_CONTAINER_USER` is more specific but still not unique in isolation.
# - All four sharing these exact names have no plausible source other than a
#   devcontainer-spec-compliant feature installer.
#
# Note: `os__is_container()` and filesystem paths are intentionally NOT used
# here. Features are installed during `docker build` (BuildKit RUN steps),
# where `/.dockerenv` is absent — `os__is_container()` returns false in that
# context. The `/tmp/dev-container-features` path is a specific CLI internal
# that other compliant tools need not replicate.
#
# Returns: 0 in devcontainer feature-install context, 1 otherwise.
os__is_devcontainer_build() {
  [ "${_REMOTE_USER+defined}" = "defined" ] &&
    [ "${_CONTAINER_USER+defined}" = "defined" ] &&
    [ "${_REMOTE_USER_HOME+defined}" = "defined" ] &&
    [ "${_CONTAINER_USER_HOME+defined}" = "defined" ]
}

# @brief os__is_container — Return 0 if running inside a container (Docker, Podman, Kubernetes, CI), 1 otherwise.
#
# Uses the same heuristics as Homebrew's `check-run-command-as-root()` so that
# brew can run as root in devcontainers.
os__is_container() {
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0
  if [ -f /proc/1/cgroup ] &&
    grep -qE 'azpl_job|actions_job|docker|garden|kubepods' /proc/1/cgroup 2> /dev/null; then
    return 0
  fi
  return 1
}

# @brief _os__load_release — Parse `/etc/os-release` once and cache `ID`, `ID_LIKE`, and `VERSION_CODENAME` into module-private globals.
#
# Uses `grep`/`sed` rather than `source /etc/os-release` to avoid polluting
# the environment with the full set of os-release variables. Idempotent: sets
# `_OS__RELEASE_LOADED` after the first parse and returns immediately on
# subsequent calls. Falls back to `UBUNTU_CODENAME` when `VERSION_CODENAME`
# is absent (some Ubuntu 22.04 images omit it).
#
# Side effects: sets `_OS__ID`, `_OS__ID_LIKE`, `_OS__CODENAME`,
#               and `_OS__RELEASE_LOADED`.
_os__load_release() {
  [ -n "${_OS__RELEASE_LOADED-}" ] && return 0
  if [ -f /etc/os-release ]; then
    _OS__ID="$(grep -m1 '^ID=' /etc/os-release 2> /dev/null |
      sed 's/^ID=//;s/^"//;s/"$//')"
    _OS__ID_LIKE="$(grep -m1 '^ID_LIKE=' /etc/os-release 2> /dev/null |
      sed 's/^ID_LIKE=//;s/^"//;s/"$//')"
    _OS__CODENAME="$(grep -m1 '^VERSION_CODENAME=' /etc/os-release 2> /dev/null |
      sed 's/^VERSION_CODENAME=//;s/^"//;s/"$//')"
    # Fallback: UBUNTU_CODENAME (present on some Ubuntu releases that lack VERSION_CODENAME).
    if [ -z "${_OS__CODENAME-}" ]; then
      _OS__CODENAME="$(grep -m1 '^UBUNTU_CODENAME=' /etc/os-release 2> /dev/null |
        sed 's/^UBUNTU_CODENAME=//;s/^"//;s/"$//')"
    fi
  fi
  _OS__RELEASE_LOADED=1
  return 0
}

# @brief os__codename — Print `VERSION_CODENAME` from `/etc/os-release` (e.g. `jammy`, `bookworm`); empty string if absent or on macOS.
#
# Falls back to `UBUNTU_CODENAME` when `VERSION_CODENAME` is absent.
#
# Stdout: distro codename, or empty string.
os__codename() {
  _os__load_release
  echo "${_OS__CODENAME:-}"
  return 0
}

# @brief os__match_spec <key=value> [...] — Return 0 if the current OS context matches all given key=value conditions.
#
# Delegates to `ospkg__os_release_match` (which calls `ospkg__detect` idempotently).
# AND logic: all key=value pairs must match. Case-insensitive.
# Supported keys: kernel, arch, id, id_like, pm, version_id, version_codename, and any
# /etc/os-release field.
#
# Returns: 0 if all conditions match, 1 otherwise.
os__match_spec() {
  [ $# -eq 0 ] && return 0
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    ospkg__os_release_match "$_k" "$_v" || {
      logging__error "platform condition '${_pair}' did not match."
      return 1
    }
  done
  return 0
}

# @brief os__expand_release_pattern <pattern> <version> <tag> — Expand a GitHub release
# asset filename pattern.
#
# Plain tokens: {VERSION}, {TAG}, {OS}, {KERNEL}, {ARCH}, {OS_ARCH}, {OS_ID},
#   {PLATFORM}, {RUST_TRIPLE}.
# Flavor tokens: {OS:<flavor>} → os__release_kernel <flavor>,
#   {ARCH:<flavor>} → os__release_arch --flavor <flavor>.
# Conditionals (nestable): {TOKEN==VALUE?TRUE:FALSE},
#   {TOKEN:FLAVOR==VALUE?TRUE:FALSE}, {VERSION>=X.Y?TRUE:FALSE},
#   {VERSION<X.Y?TRUE:FALSE}.
# TRUE and FALSE branches may themselves contain any token form.
#
# <version> and <tag> may be empty strings.
os__expand_release_pattern() {
  _os__expand_pattern_recursive "${1}" "${2:-}" "${3:-}" || {
    logging__error "failed to expand release pattern '${1}'."
    return 1
  }
  printf '\n'
}

# @brief _os__find_close_brace <str> — Output the 0-based index of the '}' that closes
# the '{' preceding <str> (i.e. <str> begins just after an opening '{').
# Returns 1 if no matching brace is found.
_os__find_close_brace() {
  local _s="$1" _depth=1 _i=0
  while [[ ${_i} -lt ${#_s} ]]; do
    case "${_s:${_i}:1}" in
      '{') ((_depth++)) ;;
      '}')
        ((_depth--))
        [[ ${_depth} -eq 0 ]] && {
          printf '%d' "${_i}"
          return 0
        }
        ;;
    esac
    ((_i++))
  done
  return 1
}

# @brief _os__split_conditional <token> <cond_var> <true_var> <false_var>
# Splits 'COND?TRUE:FALSE' at the first depth-0 '?' and subsequent depth-0 ':'.
# Populates name-ref vars; returns 1 if no depth-0 '?' exists (not a conditional).
_os__split_conditional() {
  local _tok="$1"
  local -n _sc_cond="$2" _sc_true="$3" _sc_false="$4"
  local _i=0 _depth=0 _qpos=-1 _cpos=-1
  while [[ ${_i} -lt ${#_tok} ]]; do
    case "${_tok:${_i}:1}" in
      '{') ((_depth++)) ;;
      '}') ((_depth--)) ;;
      '?') [[ ${_depth} -eq 0 ]] && {
        _qpos=${_i}
        break
      } ;;
    esac
    ((_i++))
  done
  [[ ${_qpos} -eq -1 ]] && return 1
  _sc_cond="${_tok:0:${_qpos}}"
  local _rest="${_tok:$((_qpos + 1))}"
  _i=0
  _depth=0
  while [[ ${_i} -lt ${#_rest} ]]; do
    case "${_rest:${_i}:1}" in
      '{') ((_depth++)) ;;
      '}') ((_depth--)) ;;
      ':') [[ ${_depth} -eq 0 ]] && {
        _cpos=${_i}
        break
      } ;;
    esac
    ((_i++))
  done
  [[ ${_cpos} -eq -1 ]] && return 1
  _sc_true="${_rest:0:${_cpos}}"
  _sc_false="${_rest:$((_cpos + 1))}"
  return 0
}

# @brief _os__eval_condition <condition> <version> — Return 0 if condition is true.
# Supports: VERSION>=X, VERSION<X, VERSION==X, OS==V, ARCH==V, OS:F==V, ARCH:F==V.
_os__eval_condition() {
  local _cond="$1" _ver="$2"
  if [[ "${_cond}" =~ ^VERSION\>=(.+)$ ]]; then
    ver__semver_ge "${_ver}" "${BASH_REMATCH[1]}"
  elif [[ "${_cond}" =~ ^VERSION\<(.+)$ ]]; then
    ! ver__semver_ge "${_ver}" "${BASH_REMATCH[1]}"
  elif [[ "${_cond}" =~ ^VERSION==(.+)$ ]]; then
    [[ "${_ver}" == "${BASH_REMATCH[1]}" ]]
  elif [[ "${_cond}" =~ ^OS:([^=]+)==(.+)$ ]]; then
    local _actual
    _actual="$(os__release_kernel "${BASH_REMATCH[1]}")" || {
      logging__error "failed to detect OS kernel flavor '${BASH_REMATCH[1]}'."
      return 1
    }
    [[ "${_actual}" == "${BASH_REMATCH[2]}" ]]
  elif [[ "${_cond}" =~ ^ARCH:([^=]+)==(.+)$ ]]; then
    local _actual
    _actual="$(os__release_arch --flavor "${BASH_REMATCH[1]}")" || {
      logging__error "failed to detect CPU architecture flavor '${BASH_REMATCH[1]}'."
      return 1
    }
    [[ "${_actual}" == "${BASH_REMATCH[2]}" ]]
  elif [[ "${_cond}" =~ ^OS==(.+)$ ]]; then
    [[ "$(os__release_kernel)" == "${BASH_REMATCH[1]}" ]]
  elif [[ "${_cond}" =~ ^ARCH==(.+)$ ]]; then
    [[ "$(os__release_arch)" == "${BASH_REMATCH[1]}" ]]
  else
    logging__error "unsupported condition '${_cond}'."
    return 1
  fi
}

# @brief _os__eval_token <token_content> <version> <tag> — Expand one {…} block.
_os__eval_token() {
  local _tok="$1" _ver="$2" _tag="$3"
  local _cond _tbranch _fbranch
  if _os__split_conditional "${_tok}" _cond _tbranch _fbranch; then
    if _os__eval_condition "${_cond}" "${_ver}"; then
      _os__expand_pattern_recursive "${_tbranch}" "${_ver}" "${_tag}"
    else
      _os__expand_pattern_recursive "${_fbranch}" "${_ver}" "${_tag}"
    fi
    return
  fi
  if [[ "${_tok}" =~ ^OS:(.+)$ ]]; then
    os__release_kernel "${BASH_REMATCH[1]}" || {
      logging__error "failed to expand OS kernel flavor '${BASH_REMATCH[1]}'."
      return 1
    }
    return
  fi
  if [[ "${_tok}" =~ ^ARCH:(.+)$ ]]; then
    os__release_arch --flavor "${BASH_REMATCH[1]}" || {
      logging__error "failed to expand CPU architecture flavor '${BASH_REMATCH[1]}'."
      return 1
    }
    return
  fi
  case "${_tok}" in
    VERSION) printf '%s' "${_ver}" ;;
    TAG) printf '%s' "${_tag}" ;;
    OS) os__release_kernel ;;
    KERNEL) os__kernel ;;
    ARCH) os__release_arch ;;
    OS_ARCH) os__arch ;;
    OS_ID) os__id ;;
    PLATFORM) os__platform ;;
    RUST_TRIPLE) os__rust_triple ;;
    *)
      logging__error "unknown token '{${_tok}}'."
      return 1
      ;;
  esac
}

# @brief _os__expand_pattern_recursive <pattern> <version> <tag> — Core recursive expander.
_os__expand_pattern_recursive() {
  local _s="$1" _ver="$2" _tag="$3"
  local _result="" _i=0 _len="${#_s}"
  while [[ ${_i} -lt ${_len} ]]; do
    local _c="${_s:${_i}:1}"
    if [[ "${_c}" == '{' ]]; then
      local _after="${_s:$((_i + 1))}"
      local _cpos
      _cpos="$(_os__find_close_brace "${_after}")" || {
        logging__error "unmatched '{' in pattern."
        return 1
      }
      local _tok="${_after:0:${_cpos}}"
      local _expanded
      _expanded="$(_os__eval_token "${_tok}" "${_ver}" "${_tag}")" || {
        logging__error "failed to expand token '{${_tok}}'."
        return 1
      }
      _result+="${_expanded}"
      _i=$((_i + _cpos + 2))
    else
      _result+="${_c}"
      ((_i++))
    fi
  done
  printf '%s' "${_result}"
}
