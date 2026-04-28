#!/usr/bin/env bash
# shellcheck disable=SC2016
# (jq filter bodies use $foo for jq-side bindings; shellcheck flags single-quoted jq.)
# install.bash — Full bash >=4 implementation of the sysset installer.
#
# Invoked by install.sh after bash >=4 is confirmed. Downloads lib/*.sh from the
# repo, then operates in one of two modes:
#
#   Feature mode:   install a single feature (optionally version-pinned via :)
#   Manifest mode:  install multiple features from a devcontainer.json[.jsonc] manifest
#
# Version resolution modes:
#   Rolling (default):       each feature resolves from OCI tags independently.
#   Explicit per-feature:    `feature:version` (CLI) or features[].version in
#                            devcontainer manifest.
#
# Usage:
#   install.bash <feature>[:<feature-version>] [feature-opts...]
#   install.bash <devcontainer.json|.jsonc>
#
# Options (consumed by install.bash; not forwarded to feature installers in manifest mode):
#   --log_file <path>  Append captured output to this file on exit.
#   --log_level <level>  Log verbosity: silent|error|warn|info|debug|trace.
#   --help, -h        Show this help.
#   --workspace-folder <path>  Default cwd for init/lifecycle (manifest); feature mode default CWD.
#   --no-initialize-command    Skip devcontainer "initializeCommand" (manifest only).
#   --initialize-command-dir <path>  CWD for initializeCommand.
#   --lifecycle-command-dir <path>  CWD for all lifecycle commands.
#   --no-feature-lifecycle-command <path>  Repeat. Disable feature lifecycle (grammar: all, feature, phase, ...).
#   --no-container-lifecycle-command <path>  Repeat. Disable devcontainer.json lifecycle entries.
#   --compatible-prefix <oci-prefix>  Repeat. Default: ghcr.io/quantized8/sysset/
#   --no-lifecycle   Feature mode: skip the installed feature's lifecycle hooks.
#   --local-registry <path>  Registry root (manifest.json + features/). Default: directory of this install.bash, or SYSSET_LOCAL_REGISTRY.
#   --download-only   Fetch into the local registry and update manifest.json; do not run installers (see plan).
#   --report-file <path>  With --download-only: JSON summary of partial failures.
#   --lockfile <path>  Write resolved immutable feature refs after manifest installs.
#   --frozen-lockfile <path>  Require lockfile entries and install exactly those refs.
#
# Environment overrides:
#   SYSSET_RAW_BASE   Raw GitHub base URL       (default: main branch)
#   SYSSET_FETCH_TOOL curl|wget                 (set by install.sh; auto-detected here if unset)
#   SYSSET_GHCR_NAMESPACE  GHCR namespace path for oci__ refs (default: quantized8/sysset)
#   SYSSET_LOCAL_REGISTRY  Optional directory override for the local registry root.
#   SYSSET_VERSION    Ignored by installer (bundle pinning removed).
set -euo pipefail

SYSSET_REPO="quantized8/sysset"
SYSSET_RAW_BASE="${SYSSET_RAW_BASE:-https://raw.githubusercontent.com/${SYSSET_REPO}/main}"
SYSSET_GHCR_NAMESPACE="${SYSSET_GHCR_NAMESPACE:-quantized8/sysset}"

# ── Lib bootstrap ─────────────────────────────────────────────────────────────
# Download lib/*.sh before anything else. SYSSET_FETCH_TOOL is set by install.sh;
# fall back to curl detection here in case install.bash is invoked directly.

if [[ -z "${SYSSET_FETCH_TOOL:-}" ]]; then
  if command -v curl > /dev/null 2>&1; then
    SYSSET_FETCH_TOOL="curl"
  elif command -v wget > /dev/null 2>&1; then
    SYSSET_FETCH_TOOL="wget"
  else
    echo "⛔ Neither curl nor wget found. Install one and retry." >&2
    exit 1
  fi
fi

_lib_tmpdir="$(mktemp -d)"
_lib_dir="${_lib_tmpdir}/_lib"
mkdir "$_lib_dir"

# Tiny fetch helper used only for the initial lib download (net.sh not yet sourced).
_bootstrap_fetch() {
  # $1=url $2=dest
  if [[ "${SYSSET_FETCH_TOOL}" == "wget" ]]; then
    wget -qO "$2" --tries=3 --waitretry=5 "$1"
  else
    curl -fsSL --retry 3 --retry-delay 5 "$1" -o "$2"
  fi
}

echo "ℹ️  Downloading sysset lib files..." >&2
for _f in net.sh os.sh str.sh json.sh github.sh ospkg.sh logging.sh checksum.sh oci.sh lock.sh graph.sh proc.sh devcontainer.sh jsonc.py users.sh; do
  _bootstrap_fetch "${SYSSET_RAW_BASE}/lib/${_f}" "${_lib_dir}/${_f}"
done
unset -f _bootstrap_fetch

# _SYSSET_LIB_DIR is read by github.sh when it loads json.sh.
_SYSSET_LIB_DIR="$_lib_dir"

# shellcheck source=lib/ospkg.sh
. "${_lib_dir}/ospkg.sh" # also sources os.sh and net.sh
# shellcheck source=lib/logging.sh
. "${_lib_dir}/logging.sh"
# shellcheck source=lib/github.sh
. "${_lib_dir}/github.sh"
# shellcheck source=lib/checksum.sh
. "${_lib_dir}/checksum.sh"
# shellcheck source=lib/oci.sh
. "${_lib_dir}/oci.sh"
# shellcheck source=lib/lock.sh
. "${_lib_dir}/lock.sh"
# shellcheck source=lib/str.sh
. "${_lib_dir}/str.sh"
# shellcheck source=lib/graph.sh
. "${_lib_dir}/graph.sh"
# shellcheck source=lib/proc.sh
. "${_lib_dir}/proc.sh"
# shellcheck source=lib/devcontainer.sh
. "${_lib_dir}/devcontainer.sh"
# shellcheck source=lib/users.sh
. "${_lib_dir}/users.sh"

logging__setup
trap 'rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT

logging__entry "sysset installer"

# ── Canonical install order ───────────────────────────────────────────────────
_CANONICAL_ORDER=(
  setup-user
  install-homebrew
  install-os-pkg
  install-git
  install-gh
  install-shell
  install-miniforge
  install-conda-env
  install-pixi
  install-node
  install-podman
  install-fonts
  setup-shim
)

# ── Usage ─────────────────────────────────────────────────────────────────────
__usage__() {
  cat >&2 << 'EOF'
Usage:
  Feature mode:   install.sh <feature>[:<feature-version>] [feature-opts...]
  Devcontainer:    install.sh <devcontainer.json[.jsonc]>

Options (see also header comment in install.bash):
  --log_file, --log_level, --help
  --workspace-folder, --no-initialize-command, --initialize-command-dir, --lifecycle-command-dir
  --no-feature-lifecycle-command, --no-container-lifecycle-command, --compatible-prefix
  --no-lifecycle (feature mode: skip that feature's post-install hooks)
  --local-registry <path>   Registry root: manifest.json + features/ (overrides SYSSET_LOCAL_REGISTRY)
  --download-only           Stage tarballs and update registry only; do not run installers
  --report-file <path>      With --download-only: write JSON ok/failures (manifest mode)

Version priority: explicit OCI :tag/@digest  >  per-feature version spec  >  latest
  (Use ``feature:version`` — ``@`` is not supported.)
EOF
  exit "${1:-0}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
LOG_FILE="${LOG_FILE:-}"
LOG_LEVEL="${LOG_LEVEL:-info}"
_mode_arg=""
_WORKSPACE_CUSTOM=""
_NO_INIT_CMD=false
_INIT_CMD_DIR=""
_LIFE_CMD_DIR=""
_NO_FE_LIFE=()
_NO_CO_LIFE=()
_COMPAT_PREFIX=("ghcr.io/quantized8/sysset/")
_FEATURE_SKIP_LIFECYCLE=false
_DOWNLOAD_ONLY=false
_REPORT_FILE=""
_SYSSET_REGISTRY_ROOT=""
_LOCKFILE_PATH=""
_FROZEN_LOCKFILE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log_file)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--log_file requires a value."
        exit 1
      }
      LOG_FILE="$1"
      shift
      ;;
    --log_level)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--log_level requires a value."
        exit 1
      }
      LOG_LEVEL="$1"
      shift
      ;;
    --help | -h) __usage__ ;;
    --workspace-folder)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--workspace-folder needs a value."
        exit 1
      }
      _WORKSPACE_CUSTOM="$1"
      shift
      ;;
    --no-initialize-command)
      _NO_INIT_CMD=true
      shift
      ;;
    --initialize-command-dir)
      shift
      _INIT_CMD_DIR="${1-}"
      shift
      ;;
    --lifecycle-command-dir)
      shift
      _LIFE_CMD_DIR="${1-}"
      shift
      ;;
    --no-feature-lifecycle-command)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--no-feature-lifecycle-command needs a value."
        exit 1
      }
      _NO_FE_LIFE+=("$1")
      shift
      ;;
    --no-container-lifecycle-command)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--no-container-lifecycle-command needs a value."
        exit 1
      }
      _NO_CO_LIFE+=("$1")
      shift
      ;;
    --compatible-prefix)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--compatible-prefix needs a value."
        exit 1
      }
      _COMPAT_PREFIX+=("$1")
      shift
      ;;
    --no-lifecycle)
      _FEATURE_SKIP_LIFECYCLE=true
      shift
      ;;
    --local-registry)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--local-registry needs a path."
        exit 1
      }
      _SYSSET_REGISTRY_ROOT="$(cd "$1" && pwd -P)"
      shift
      ;;
    --download-only)
      _DOWNLOAD_ONLY=true
      shift
      ;;
    --report-file)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--report-file needs a path."
        exit 1
      }
      _REPORT_FILE="$1"
      shift
      ;;
    --lockfile)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--lockfile needs a path."
        exit 1
      }
      _LOCKFILE_PATH="$1"
      shift
      ;;
    --frozen-lockfile)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--frozen-lockfile needs a path."
        exit 1
      }
      _FROZEN_LOCKFILE_PATH="$1"
      shift
      ;;
    --*)
      logging__error "Unknown option: '${1}'"
      exit 1
      ;;
    *)
      _mode_arg="$1"
      shift
      break
      ;;
  esac
done

if [[ -z "$_SYSSET_REGISTRY_ROOT" ]]; then
  if [[ -n "${SYSSET_LOCAL_REGISTRY:-}" ]]; then
    _SYSSET_REGISTRY_ROOT="$(cd "${SYSSET_LOCAL_REGISTRY}" && pwd -P)"
  else
    _SYSSET_REGISTRY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  fi
fi

logging__set_level

if [[ "$_DOWNLOAD_ONLY" == true ]]; then
  _json__ensure_jq || {
    logging__error "--download-only requires jq (json.sh could not install it)."
    exit 1
  }
fi

if [[ -z "$_mode_arg" ]]; then
  logging__error "No feature or manifest specified."
  __usage__ 1
fi
if [[ -n "$_LOCKFILE_PATH" && -n "$_FROZEN_LOCKFILE_PATH" && "$_LOCKFILE_PATH" != "$_FROZEN_LOCKFILE_PATH" ]]; then
  logging__error "--lockfile and --frozen-lockfile must reference the same path when both are set."
  exit 1
fi

# ── Mode detection ────────────────────────────────────────────────────────────
_mode=""
case "$_mode_arg" in
  *.json | *.jsonc) _mode="manifest" ;;
  *) _mode="feature" ;;
esac

# ── Per-feature version resolution ──────────────────────────────────────────
_sysset_repo_ref_for_feature() {
  local _feature="${1-}"
  printf 'ghcr.io/%s/%s\n' "${SYSSET_GHCR_NAMESPACE}" "${_feature,,}"
}

_sysset_verify_digest_checksums() {
  local _root="${1%/}" _dkey="${2-}" _mf="${3-}" _rp _ent _path _sum _expect
  _json__ensure_jq || return 1
  _rp="$(json__query -r --arg d "$_dkey" '.digests[$d].relativePath // empty' "$_mf" 2> /dev/null)" || _rp=""
  [[ -n "$_rp" && "$_rp" != "null" ]] || return 1
  while IFS=$'\t' read -r _ent _expect; do
    [[ -z "$_ent" || "$_ent" == "null" ]] && continue
    _path="${_root}/${_rp%/}/${_ent}"
    [[ -f "$_path" ]] || {
      logging__error "local registry: missing payload file ${_path}"
      return 1
    }
    _sum="$(checksum__sha256_file "$_path")" || return 1
    if [[ "${_sum}" != "${_expect}" ]]; then
      logging__error "local registry: checksum mismatch for ${_ent}"
      return 1
    fi
  done < <(json__query -r --arg d "$_dkey" '.digests[$d].checksums // {} | to_entries[] | "\(.key)\t\(.value)"' "$_mf" 2> /dev/null)
  return 0
}

_sysset_pack_digest_payload_to_tarball() {
  local _root="${1%/}" _dkey="${2-}" _mf="${3-}" _dest="${4-}" _rp _d
  _json__ensure_jq || return 1
  _rp="$(json__query -r --arg d "$_dkey" '.digests[$d].relativePath // empty' "$_mf" 2> /dev/null)" || _rp=""
  [[ -n "$_rp" && "$_rp" != "null" ]] || return 1
  _d="${_root}/${_rp}"
  [[ -d "$_d" ]] || return 1
  tar -czf "$_dest" -C "$_d" .
  return 0
}

# shellcheck disable=SC2329 # called from _sysset_manifest_registry_append_unlocked (dynamic analysis misses eval chain)
_sysset_checksums_json_for_payload_dir() {
  local _d="${1-}" _j="{}"
  local _f _h
  _json__ensure_jq || return 1
  for _f in install.sh install.bash devcontainer-feature.json; do
    [[ -f "${_d}/${_f}" ]] || continue
    _h="$(checksum__sha256_file "${_d}/${_f}")" || return 1
    _j="$(json__query -n --argjson cur "$_j" --arg k "$_f" --arg v "$_h" '$cur + {($k): $v}')"
  done
  printf '%s\n' "$_j"
}

_sysset_manifest_registry_append() {
  local _root="${1%/}" _ref="$2" _tb="$3"
  local _mf="${_root}/manifest.json"
  [[ -f "$_mf" ]] || return 1
  [[ -f "$_tb" ]] || return 1
  lock__run_with_lockfile "${_mf}.lock" "$(printf '_sysset_manifest_registry_append_unlocked %q %q %q' "$_root" "$_ref" "$_tb")"
}

# shellcheck disable=SC2329 # invoked via eval from lock__run_with_lockfile (see _sysset_manifest_registry_append)
_sysset_manifest_registry_append_unlocked() {
  local _root="${1%/}" _ref="$2" _tb="$3"
  local _mf="${_root}/manifest.json"
  local _hex _dkey _rel _dest _now _chk _tmp _repo
  _hex="$(checksum__sha256_file "$_tb")" || return 1
  _dkey="sha256:${_hex}"
  _repo="$(_oci__repo_from_ref "$_ref")"
  _repo="${_repo,,}"
  _rel="features/${_repo}/sha256/${_hex}/"
  _dest="${_root}/${_rel}"
  _ref="${_ref,,}"
  _now="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2> /dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"
  [[ -d "$_dest" ]] && rm -rf "$_dest"
  mkdir -p "$_dest"
  tar -xzf "$_tb" -C "$_dest" || return 1
  _chk="$(_sysset_checksums_json_for_payload_dir "$_dest")" || return 1
  _tmp="${_mf}.tmp.$$"
  if ! json__query \
    --arg ref "$_ref" \
    --arg dig "$_dkey" \
    --arg rp "$_rel" \
    --arg fa "$_now" \
    --argjson chk "$_chk" \
    --argjson digestsprev "$(json__query -c '.digests // {}' "$_mf" 2> /dev/null || echo '{}')" \
    '
    .refs[$ref] = $dig
    | .digests[$dig] = (
        {
          relativePath: $rp,
          fetchedAt: $fa,
          sourceRefs: (
            ( ($digestsprev[$dig].sourceRefs // []) + [$ref] ) | unique
          ),
          checksums: $chk
        }
      )
    ' "$_mf" > "$_tmp"; then
    rm -rf "$_dest"
    rm -f "$_tmp"
    return 1
  fi
  mv "$_tmp" "$_mf" || {
    rm -rf "$_dest"
    rm -f "$_tmp"
    return 1
  }
  return 0
}

# ── Shared tarball fetch + verify ────────────────────────────────────────────
_fetch_and_verify_tarball() {
  # $1 = feature label/id, $2 = resolved oci ref, $3 = destination file
  local _feature="$1" _resolved="$2" _dest="$3"
  local _ref _norm _mf _dkey
  _mf="${_SYSSET_REGISTRY_ROOT}/manifest.json"
  _ref="${_resolved}"
  _norm="${_ref,,}"
  if [[ "$_norm" == *@sha256:* && -f "$_mf" ]]; then
    _dkey="${_norm##*@}"
    _dkey="$(json__query -r --arg r "$_norm" '.refs[$r] // empty' "$_mf" 2> /dev/null)" || _dkey=""
    [[ -n "$_dkey" && "$_dkey" != "null" ]] || _dkey="${_norm##*@}"
    if [[ -n "$_dkey" && "$_dkey" != "null" ]]; then
      if _sysset_verify_digest_checksums "$_SYSSET_REGISTRY_ROOT" "$_dkey" "$_mf" &&
        _sysset_pack_digest_payload_to_tarball "$_SYSSET_REGISTRY_ROOT" "$_dkey" "$_mf" "$_dest"; then
        logging__info "[${_feature}] using local registry (${_dkey})."
        return 0
      fi
      logging__warn "[${_feature}] local registry digest failed verification — refetching."
    fi
  fi
  local _pulled=0 _tmp
  _tmp="$(mktemp)"
  if oci__pull_feature_tgz "$_ref" "$_tmp"; then
    if mv "$_tmp" "$_dest"; then
      _pulled=1
    else
      logging__warn "[${_feature}] OCI pull succeeded but could not move payload to destination; trying local cache fallback."
    fi
  fi
  if [[ "$_pulled" -eq 0 && -f "$_mf" ]]; then
    _dkey="$(json__query -r --arg r "$_norm" '.refs[$r] // empty' "$_mf" 2> /dev/null)" || _dkey=""
    if [[ -n "$_dkey" && "$_dkey" != "null" ]] &&
      _sysset_verify_digest_checksums "$_SYSSET_REGISTRY_ROOT" "$_dkey" "$_mf" &&
      _sysset_pack_digest_payload_to_tarball "$_SYSSET_REGISTRY_ROOT" "$_dkey" "$_mf" "$_dest"; then
      logging__warn "[${_feature}] registry unreachable; using cached ref ${_norm}."
      _pulled=2
    fi
  fi
  rm -f "$_tmp"
  [[ "$_pulled" -ne 0 ]] || return 1
  if [[ -f "$_mf" && -w "$_mf" ]]; then
    _sysset_manifest_registry_append "$_SYSSET_REGISTRY_ROOT" "$_norm" "$_dest" || {
      logging__warn "[${_feature}] could not update local manifest.json."
    }
  fi
  return 0
}

# ── Resolve (feature, spec, key) → oci-ref ──────────────────────────────────
_sysset_is_registry_host_like() {
  local _host="${1-}"
  [[ -n "$_host" ]] || return 1
  [[ "$_host" == "localhost" || "$_host" =~ ^localhost:[0-9]+$ ]] && return 0
  [[ "$_host" == *.* ]] && return 0
  [[ "$_host" =~ ^\[[0-9A-Fa-f:.]+\](:[0-9]+)?$ ]] && return 0
  return 1
}

_resolve_install_tag() {
  local _feature="$1" _spec="${2:-}" _key="${3:-}" _repo="" _tag="" _raw=""
  if [[ -n "$_key" && "$_key" != "$_feature" ]]; then
    _raw="$_key"
  else
    _raw="$_feature"
  fi

  if [[ "$_raw" == */* ]] && _sysset_is_registry_host_like "${_raw%%/*}"; then
    _repo="$(_oci__repo_from_ref "$_raw")"
    if [[ "$_raw" == *@sha256:* ]]; then
      printf '%s\n' "${_raw,,}"
      return 0
    fi
    if [[ -n "$_spec" ]]; then
      _tag="$(oci__resolve_version "$_repo" "$_spec")" || return 1
      printf '%s:%s\n' "${_repo,,}" "$_tag"
      return 0
    fi
    if _tag="$(_oci__tag_from_ref "$_raw" 2> /dev/null || true)" && [[ -n "$_tag" ]]; then
      printf '%s\n' "${_raw,,}"
      return 0
    fi
    printf '%s:latest\n' "${_repo,,}"
    return 0
  fi

  _repo="$(_sysset_repo_ref_for_feature "$_feature")"
  _tag="$(oci__resolve_version "$_repo" "$_spec")" || return 1
  printf '%s:%s\n' "${_repo,,}" "$_tag"
}

_sysset_lockfile_lookup_ref() {
  local _lf="${1-}" _key="${2-}"
  [[ -f "$_lf" ]] || return 1
  json__query -r --arg k "$_key" '.features[$k].resolved // empty' "$_lf" 2> /dev/null
}

_sysset_lockfile_write() {
  local _path="${1-}"
  [[ -n "$_path" ]] || return 0
  local _tmp
  _tmp="${_path}.tmp.$$"
  : > "$_tmp"
  {
    printf '{\n  "schemaVersion": "1",\n  "features": {\n'
    local _first=1 _k
    for _k in "${!_LOCK_RESOLVED[@]}"; do
      local _resolved="${_LOCK_RESOLVED[$_k]}"
      local _json_line
      _json_line="$(json__query -n --arg k "$_k" --arg r "$_resolved" '{"k":$k,"r":$r}')" || return 1
      local _kk _rr
      _kk="$(printf '%s' "$_json_line" | json__query -r '.k')" || return 1
      _rr="$(printf '%s' "$_json_line" | json__query -r '.r')" || return 1
      if [[ $_first -eq 0 ]]; then
        printf ',\n'
      fi
      _first=0
      printf '    "%s": { "resolved": "%s" }' "$_kk" "$_rr"
    done
    printf '\n  }\n}\n'
  } > "$_tmp"
  mv "$_tmp" "$_path"
}

# _sysset_options_to_env — apply options JSON (stdin) as exported env vars in current shell.
# Newlines inside string values are preserved via bash %q quoting (in devcontainer__feature_env_exports).
_sysset_options_to_env() {
  local _exports
  _exports="$(devcontainer__feature_env_exports)" || return 1
  [[ -n "$_exports" ]] && eval "$_exports"
  return 0
}

# _sysset_disabled_fe <entry...>,<fid>,<phase>,<cmdname> — scan _NO_FE_LIFE for feature-scope skip.
_sysset_disabled_fe() {
  local _fid="$1" _ph="$2" _cn="${3-}" _e
  for _e in "${_NO_FE_LIFE[@]+"${_NO_FE_LIFE[@]}"}"; do
    devcontainer__lifecycle_disabled "$_e" feature "$_fid" "$_ph" "$_cn" && return 0
  done
  return 1
}

# _sysset_disabled_co <phase> <cmdname> — scan _NO_CO_LIFE for container-scope skip.
_sysset_disabled_co() {
  local _ph="$1" _cn="${2-}" _e
  for _e in "${_NO_CO_LIFE[@]+"${_NO_CO_LIFE[@]}"}"; do
    devcontainer__lifecycle_disabled "$_e" container "_container_" "$_ph" "$_cn" && return 0
  done
  return 1
}

# _sysset_warn_unknown_fe_scope <fid> — warn about feature-scope disable entries whose
# feature id does not match the single installed feature (feature-mode only).
_sysset_warn_unknown_fe_scope() {
  local _fid="$1" _e _head
  for _e in "${_NO_FE_LIFE[@]+"${_NO_FE_LIFE[@]}"}"; do
    [[ -z "$_e" || "$_e" == "all" ]] && continue
    _head="${_e%%:*}"
    local _isphase=0 _p
    for _p in "${_DEVCONTAINER_LIFECYCLE_PHASES[@]}"; do
      [[ "$_head" == "$_p" ]] && _isphase=1
    done
    ((_isphase)) && continue
    [[ "$_head" == "$_fid" ]] && continue
    logging__warn "--no-feature-lifecycle-command '$_e' references a different feature (installed: '$_fid'); ignoring."
  done
}

# _sysset_run_feature_lifecycle <staged-root> <fid> <cwd>
_sysset_run_feature_lifecycle() {
  local _root="${1-}" _fid="${2-}" _w="${3:-$PWD}" _ph _line _scope _sid _cmd
  local _df="${_root}/devcontainer-feature.json"
  [[ -f "$_df" ]] || {
    logging__info "No devcontainer-feature.json; skipping feature lifecycle"
    return 0
  }
  _sysset_warn_unknown_fe_scope "$_fid"
  local _stage_root
  _stage_root="$(dirname "$_root")"
  local _stage_name
  _stage_name="$(basename "$_root")"
  if [[ ! -d "${_stage_root}/${_fid}" ]]; then
    _stage_root="$_root"
    _stage_name=""
  fi
  for _ph in "${_DEVCONTAINER_LIFECYCLE_PHASES[@]}"; do
    while IFS=$'\t' read -r _scope _sid _cmd; do
      [[ "$_scope" == feature ]] || continue
      if _sysset_disabled_fe "$_sid" "$_ph" ""; then
        logging__info "[${_sid}] skip feature ${_ph} (disabled)"
        continue
      fi
      printf '%s' "$_cmd" | proc__run_command_form --cwd "$_w" || return 1
    done < <(
      if [[ -n "$_stage_name" ]]; then
        devcontainer__lifecycle_iter --staged-root "$_stage_root" --phase "$_ph" -- "$_stage_name" 2> /dev/null
      else
        local _tmpd
        _tmpd="$(mktemp -d)"
        mkdir -p "${_tmpd}/${_fid}"
        cp "$_df" "${_tmpd}/${_fid}/devcontainer-feature.json"
        devcontainer__lifecycle_iter --staged-root "$_tmpd" --phase "$_ph" -- "$_fid" 2> /dev/null
        rm -rf "$_tmpd"
      fi
    )
  done
  return 0
}

# ── Feature mode ─────────────────────────────────────────────────────────────
if [[ "$_mode" == "feature" ]]; then
  [[ "$_mode_arg" == *@* ]] && {
    logging__error "Use 'feature:version' instead of 'feature@version'."
    exit 1
  }
  case "$_mode_arg" in
    ./* | ../* | /* | ~/*)
      _feature="$_mode_arg"
      _feat_version_spec=""
      ;;
    */*)
      if _sysset_is_registry_host_like "${_mode_arg%%/*}"; then
        _feature="$_mode_arg"
        _feat_version_spec=""
      elif [[ "$_mode_arg" == *:* ]]; then
        _feature="${_mode_arg%%:*}"
        _feat_version_spec="${_mode_arg#*:}"
      else
        _feature="$_mode_arg"
        _feat_version_spec=""
      fi
      ;;
    *:*)
      _feature="${_mode_arg%%:*}"
      _feat_version_spec="${_mode_arg#*:}"
      ;;
    *)
      _feature="$_mode_arg"
      _feat_version_spec=""
      ;;
  esac

  if [[ "$_DOWNLOAD_ONLY" == true ]]; then
    case "$_mode_arg" in
      ./* | ../* | /*)
        logging__error "--download-only cannot be used with a single local feature path."
        exit 1
        ;;
    esac
  fi

  if [[ "$_feature" == ./* || "$_feature" == ../* || "$_feature" == /* || "$_feature" == ~/* ]]; then
    _local_feature="${_feature/#\~/$HOME}"
    [[ -d "$_local_feature" && -f "${_local_feature}/install.sh" && -f "${_local_feature}/devcontainer-feature.json" ]] || {
      logging__error "Local feature path is invalid: ${_feature}"
      exit 1
    }
    if [[ "$_DOWNLOAD_ONLY" == true ]]; then
      logging__error "--download-only cannot be used with a local feature path."
      exit 1
    fi
    (cd "$_local_feature" && sh "./install.sh" "$@")
    _wf="${_WORKSPACE_CUSTOM:-$PWD}"
    if [[ "$_FEATURE_SKIP_LIFECYCLE" != true ]]; then
      _lf="${_LIFE_CMD_DIR:-$_wf}"
      _sysset_run_feature_lifecycle "$_local_feature" "$_feature" "$_lf" || exit 1
    fi
    logging__fn_exit "sysset installer"
    exit 0
  fi

  if ! _RESOLVED="$(_resolve_install_tag "$_feature" "$_feat_version_spec" "$_mode_arg")" || [[ -z "$_RESOLVED" ]]; then
    exit 1
  fi
  _tmpdir="$(mktemp -d)"
  trap 'rm -rf "$_lib_tmpdir" "$_tmpdir"; logging__cleanup' EXIT
  if ! _fetch_and_verify_tarball "$_feature" "$_RESOLVED" "${_tmpdir}/feature.tar.gz"; then
    exit 1
  fi
  if [[ "$_DOWNLOAD_ONLY" == true ]]; then
    logging__info "[${_feature}] --download-only: fetched ${_RESOLVED}."
    [[ -n "$_REPORT_FILE" ]] && printf '%s\n' "{\"ok\":[\"${_feature}\"]}" > "$_REPORT_FILE"
    logging__fn_exit "sysset installer"
    exit 0
  fi
  tar -xzf "${_tmpdir}/feature.tar.gz" -C "$_tmpdir"
  sh "${_tmpdir}/install.sh" "$@"
  _wf="${_WORKSPACE_CUSTOM:-$PWD}"
  if [[ "$_FEATURE_SKIP_LIFECYCLE" != true ]]; then
    _lf="${_LIFE_CMD_DIR:-$_wf}"
    _sysset_run_feature_lifecycle "$_tmpdir" "$_feature" "$_lf" || exit 1
  fi
  logging__fn_exit "sysset installer"
  exit 0
fi

# ══ Devcontainer manifest mode ══════════════════════════════════════════
if [[ ! -f "$_mode_arg" ]]; then
  logging__error "Not found: $_mode_arg"
  exit 1
fi

_DCJ="$(mktemp)"
# shellcheck disable=SC2064
trap 'rm -f "$_DCJ"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
devcontainer__parse_config "$_mode_arg" > "$_DCJ" || exit 1
declare -A _LOCK_RESOLVED=()
_ACTIVE_LOCKFILE="${_FROZEN_LOCKFILE_PATH:-${_LOCKFILE_PATH:-}}"
if [[ -n "$_FROZEN_LOCKFILE_PATH" && ! -f "$_FROZEN_LOCKFILE_PATH" ]]; then
  logging__error "--frozen-lockfile requires existing file: ${_FROZEN_LOCKFILE_PATH}"
  exit 1
fi

_WORK_ROOT="$(devcontainer__workspace_folder "$_mode_arg")"
[[ -n "$_WORKSPACE_CUSTOM" ]] && _WORK_ROOT="$_WORKSPACE_CUSTOM"

if [[ "$_DOWNLOAD_ONLY" == true ]]; then
  declare -A _D_K=() _D_T=()
  _D_IDS=()
  while IFS=$'\t' read -r _id _k _tt; do
    [[ -z "$_id" ]] && continue
    if [[ "$_k" == ./* || "$_k" == ../* || "$_k" == /* ]]; then
      continue
    fi
    _D_IDS+=("$_id")
    _D_K["$_id"]="$_k"
    _D_T["$_id"]="$_tt"
  done < <(devcontainer__iter_features "$_DCJ" "$_WORK_ROOT" "${_COMPAT_PREFIX[@]}")
  declare -A _D_SEEN=()
  _D_QUEUE=("${_D_IDS[@]}")
  _D_FAIL=()
  _D_OK=()
  while ((${#_D_QUEUE[@]} > 0)); do
    _cur="${_D_QUEUE[0]}"
    _D_QUEUE=("${_D_QUEUE[@]:1}")
    [[ -n "${_D_SEEN[$_cur]:-}" ]] && continue
    _D_SEEN["$_cur"]=1
    if [[ -n "$_FROZEN_LOCKFILE_PATH" ]]; then
      _rt="$(_sysset_lockfile_lookup_ref "$_FROZEN_LOCKFILE_PATH" "${_D_K[$_cur]}" || true)"
      [[ -n "$_rt" ]] || {
        _D_FAIL+=("$_cur")
        continue
      }
    elif ! _rt="$(_resolve_install_tag "$_cur" "${_D_T[$_cur]}" "${_D_K[$_cur]}")" || [[ -z "$_rt" ]]; then
      _D_FAIL+=("$_cur")
      continue
    fi
    _wdir="$(mktemp -d)"
    if ! _fetch_and_verify_tarball "$_cur" "$_rt" "${_wdir}/a.tgz"; then
      _D_FAIL+=("$_cur")
      rm -rf "$_wdir"
      continue
    fi
    tar -xzf "${_wdir}/a.tgz" -C "$_wdir"
    _D_OK+=("$_cur")
    _LOCK_RESOLVED["${_D_K[$_cur]}"]="${_rt,,}"
    if [[ -f "${_wdir}/devcontainer-feature.json" ]]; then
      while IFS= read -r _dep; do
        [[ -z "$_dep" || "$_dep" == "null" ]] && continue
        if [[ "$_dep" != */* ]]; then
          continue
        fi
        _drest="${_dep##*/}"
        _did="${_drest%%:*}"
        _did="${_did%%@*}"
        [[ -n "${_D_SEEN[$_did]:-}" ]] && continue
        _D_K["$_did"]="$_dep"
        _D_T["$_did"]=""
        _D_QUEUE+=("$_did")
      done < <(json__query -r '(.dependsOn // {}) | keys[]' "${_wdir}/devcontainer-feature.json" 2> /dev/null)
    fi
    rm -rf "$_wdir"
  done
  if [[ -n "$_REPORT_FILE" ]]; then
    json__query -n \
      --argjson ok "$(json__query -n '$ARGS.positional' --args -- ${_D_OK[@]+"${_D_OK[@]}"})" \
      --argjson fail "$(json__query -n '$ARGS.positional' --args -- ${_D_FAIL[@]+"${_D_FAIL[@]}"})" \
      '{ok:$ok, failures:$fail}' > "$_REPORT_FILE" 2> /dev/null || true
  fi
  if [[ -n "$_ACTIVE_LOCKFILE" ]]; then
    _sysset_lockfile_write "$_ACTIVE_LOCKFILE" || {
      logging__error "failed to write lockfile: ${_ACTIVE_LOCKFILE}"
      exit 1
    }
  fi
  ((${#_D_FAIL[@]} > 0)) && exit 1
  logging__fn_exit "sysset installer"
  exit 0
fi

os__require_root
_SYSSET_BUILD_CONTEXT="install-bash"
export _SYSSET_BUILD_CONTEXT
_SYSSET_SESSION_TRACK_DIR="$(mktemp -d)"
export _SYSSET_SESSION_TRACK_DIR
_SYSSET_INITIAL_SNAPSHOT="$(mktemp)"
export _SYSSET_INITIAL_SNAPSHOT
ospkg__take_initial_snapshot "$_SYSSET_INITIAL_SNAPSHOT"

_STAGED="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'ospkg__cleanup_session_build_groups "false"; rm -rf "${_SYSSET_SESSION_TRACK_DIR:-}" "${_SYSSET_INITIAL_SNAPSHOT:-}" "$_STAGED" "$_DCJ"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT

declare -A _KEY_OF=() _OPT_OF=() _TAG_OF=()
_IDS=()
while IFS=$'\t' read -r _id _k _tt; do
  [[ -z "$_id" ]] && continue
  _opt="$(json__query -c --arg k "$_k" '(.features // {})[$k] // {}' "$_DCJ")"
  _IDS+=("$_id")
  _KEY_OF["$_id"]="$_k"
  _OPT_OF["$_id"]="$_opt"
  _TAG_OF["$_id"]="$_tt"
done < <(devcontainer__iter_features "$_DCJ" "$_WORK_ROOT" "${_COMPAT_PREFIX[@]}")
((${#_IDS[@]})) || {
  logging__error "no features"
  exit 1
}

# Stage tarballs (skip and record failures; continue with remaining features)
_failed=()
_OK_IDS=()
for _id in "${_IDS[@]}"; do
  mkdir -p "${_STAGED}/${_id}"
  if [[ -n "$_FROZEN_LOCKFILE_PATH" ]]; then
    _rt="$(_sysset_lockfile_lookup_ref "$_FROZEN_LOCKFILE_PATH" "${_KEY_OF[$_id]}" || true)"
    [[ -n "$_rt" ]] || {
      _failed+=("$_id")
      continue
    }
  elif ! _rt="$(_resolve_install_tag "$_id" "${_TAG_OF[$_id]}" "${_KEY_OF[$_id]}")" || [[ -z "$_rt" ]]; then
    _failed+=("$_id")
    continue
  fi
  if ! _fetch_and_verify_tarball "$_id" "$_rt" "${_STAGED}/${_id}/a.tgz"; then
    _failed+=("$_id")
    continue
  fi
  if ! tar -xzf "${_STAGED}/${_id}/a.tgz" -C "${_STAGED}/${_id}"; then
    _failed+=("$_id")
    continue
  fi
  if [[ ! -f "${_STAGED}/${_id}/devcontainer-feature.json" ]]; then
    logging__error "missing devcontainer-feature.json in $_id"
    _failed+=("$_id")
    continue
  fi
  _LOCK_RESOLVED["${_KEY_OF[$_id]}"]="${_rt,,}"
  _OK_IDS+=("$_id")
done
((${#_OK_IDS[@]})) || {
  logging__error "no features could be staged"
  exit 1
}
_IDS=("${_OK_IDS[@]}")
unset _OK_IDS

# Graph files
ht="${_STAGED}/h"
st="${_STAGED}/s"
pt="${_STAGED}/p"
devcontainer__build_ordering_inputs \
  --hard-edges-file "$ht" \
  --soft-edges-file "$st" \
  --priority-file "$pt" \
  --staged-root "$_STAGED" \
  --config-file "$_DCJ" \
  -- "${_IDS[@]}" || {
  logging__error "failed to build ordering inputs"
  exit 1
}

mapfile -t _ORDER < <(graph__round_order --hard-edges-file "$ht" --soft-edges-file "$st" --priority-file "$pt" -- "${_IDS[@]}" 2> /dev/null || true)
((${#_ORDER[@]})) || {
  _ORDER=()
  for _c in "${_CANONICAL_ORDER[@]}"; do
    for _i in "${_IDS[@]}"; do
      [[ "$_c" == "$_i" ]] && _ORDER+=("$_i")
    done
  done
  for _i in "${_IDS[@]}"; do
    _in=0
    for _o in "${_ORDER[@]}"; do
      [[ "$_o" == "$_i" ]] && _in=1
    done
    ((_in)) || _ORDER+=("$_i")
  done
}
logging__info "order: ${_ORDER[*]}"

if [[ "$_NO_INIT_CMD" != true ]]; then
  _iv="$(json__query -c 'if (has("initializeCommand")|not) then null else .initializeCommand end' "$_DCJ" 2> /dev/null || echo "null")"
  if [[ -n "$_iv" && "$_iv" != "null" ]]; then
    logging__warn "initializeCommand (host): trust this config"
    (cd "${_INIT_CMD_DIR:-$_WORK_ROOT}" && printf '%s' "$_iv" | proc__run_command_form --cwd "${_INIT_CMD_DIR:-$_WORK_ROOT}") || exit 1
  fi
fi

_RU="$(json__query -r '.remoteUser // ""' "$_DCJ" 2> /dev/null | head -1)"
_CU="$(json__query -r '.containerUser // ""' "$_DCJ" 2> /dev/null | head -1)"
_SELF_USER="$(users__get_current)"
_EFF_USER="${_RU:-${_CU:-$_SELF_USER}}"
_EFF_CUSER="${_CU:-$_SELF_USER}"
_RU_HOME="$(devcontainer__user_home "$_EFF_USER" 2> /dev/null || true)"
_CU_HOME="$(devcontainer__user_home "$_EFF_CUSER" 2> /dev/null || true)"
[[ -z "$_RU_HOME" ]] && _RU_HOME="${HOME:-}"
[[ -z "$_CU_HOME" ]] && _CU_HOME="${HOME:-}"

_passed=()
for _id in "${_ORDER[@]}"; do
  if [[ ! -f "${_STAGED}/${_id}/a.tgz" || ! -f "${_STAGED}/${_id}/install.sh" ]]; then
    logging__error "[${_id}] staged payload missing; skipping."
    _failed+=("$_id")
    continue
  fi
  (
    if ! _sysset_options_to_env <<< "${_OPT_OF[$_id]-}"; then
      exit 1
    fi
    export _REMOTE_USER="${_EFF_USER}"
    export _CONTAINER_USER="${_EFF_CUSER}"
    export _REMOTE_USER_HOME="${_RU_HOME}"
    export _CONTAINER_USER_HOME="${_CU_HOME}"
    export _SYSSET_BUILD_CONTEXT="feature::${_id}"
    cd "${_STAGED}/${_id}" || exit 1
    logging__info "[${_id}] running install.sh"
    sh install.sh
  ) && _passed+=("$_id") || _failed+=("$_id")
done

_LCW="${_LIFE_CMD_DIR:-$_WORK_ROOT}"
_LIFE_USER="${_RU:-}"
for _ph in onCreateCommand updateContentCommand postCreateCommand postStartCommand postAttachCommand; do
  while IFS=$'\t' read -r _scope _sid _cmd; do
    [[ -z "$_scope" ]] && continue
    if [[ "$_scope" == feature ]]; then
      if _sysset_disabled_fe "$_sid" "$_ph" ""; then
        logging__info "[${_sid}] skip feature ${_ph} (disabled)"
        continue
      fi
    else
      if _sysset_disabled_co "$_ph" ""; then
        logging__info "skip container ${_ph} (disabled)"
        continue
      fi
    fi
    if [[ -n "$_LIFE_USER" ]]; then
      printf '%s' "$_cmd" | proc__run_command_form --cwd "$_LCW" --user "$_LIFE_USER" || exit 1
    else
      printf '%s' "$_cmd" | proc__run_command_form --cwd "$_LCW" || exit 1
    fi
  done < <(devcontainer__lifecycle_iter --config-file "$_DCJ" --staged-root "$_STAGED" --phase "$_ph" -- "${_ORDER[@]}")
done

((${#_failed[@]} > 0)) && {
  logging__error "failed: ${_failed[*]}"
  exit 1
}
if [[ -n "$_ACTIVE_LOCKFILE" ]]; then
  _sysset_lockfile_write "$_ACTIVE_LOCKFILE" || {
    logging__error "failed to write lockfile: ${_ACTIVE_LOCKFILE}"
    exit 1
  }
fi
logging__fn_exit "sysset installer"
exit 0
