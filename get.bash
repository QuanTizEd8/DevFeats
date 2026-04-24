#!/usr/bin/env bash
# get.bash — Full bash >=4 implementation of the sysset installer.
#
# Invoked by get.sh after bash >=4 is confirmed. Downloads lib/*.sh from the
# repo, then operates in one of two modes:
#
#   Feature mode:   install a single feature (optionally version-pinned via @)
#   Manifest mode:  install multiple features from a devcontainer.json[.jsonc] manifest
#
# Version resolution modes (per-feature releases are independent; the bundle
# tag `v<X.Y.Z>` is an accumulator over per-feature versions):
#
#   Rolling (default):       each feature resolves to the latest
#                            `<feature>/<X.Y.Z>` release tag independently.
#   Bundle-pinned:           `SYSSET_VERSION` (env) or `.version` (manifest)
#                            resolves to a bundle tag (`v<X.Y.Z>`); each
#                            feature's version is read from that bundle's
#                            `manifest.yaml`. Per-feature overrides (`@spec`
#                            or features[].version) still take precedence.
#
# Usage:
#   get.bash <feature>[@<feature-version>] [feature-opts...]
#   get.bash <devcontainer.json|.jsonc>
#
# Options (consumed by get.bash; not forwarded to feature installers in manifest mode):
#   --logfile <path>  Append captured output to this file on exit.
#   --debug           Enable bash -x trace.
#   --help, -h        Show this help.
#   --workspace-folder <path>  Default cwd for init/lifecycle (manifest); feature mode default CWD.
#   --no-initialize-command    Skip devcontainer "initializeCommand" (manifest only).
#   --initialize-command-dir <path>  CWD for initializeCommand.
#   --lifecycle-command-dir <path>  CWD for all lifecycle commands.
#   --no-feature-lifecycle-command <path>  Repeat. Disable feature lifecycle (grammar: all, feature, phase, ...).
#   --no-container-lifecycle-command <path>  Repeat. Disable devcontainer.json lifecycle entries.
#   --compatible-prefix <oci-prefix>  Repeat. Default: ghcr.io/quantized8/sysset/
#   --no-lifecycle   Feature mode: skip the installed feature's lifecycle hooks.
#
# Environment overrides:
#   SYSSET_BASE_URL   GitHub Releases base URL  (default: github.com releases)
#   SYSSET_RAW_BASE   Raw GitHub base URL       (default: main branch)
#   SYSSET_FETCH_TOOL curl|wget                 (set by get.sh; auto-detected here if unset)
#   SYSSET_VERSION    Pin the bundle version; feature versions are read from
#                     that bundle's manifest.yaml. Accepts any spec understood
#                     by github__resolve_version ("", "latest", "1", "1.2",
#                     "v1.2.3", "1.2.3"). Per-feature overrides still win.
set -euo pipefail

SYSSET_REPO="quantized8/sysset"
SYSSET_RELEASE_BASE="${SYSSET_BASE_URL:-https://github.com/${SYSSET_REPO}/releases/download}"
SYSSET_RAW_BASE="${SYSSET_RAW_BASE:-https://raw.githubusercontent.com/${SYSSET_REPO}/main}"

# ── Lib bootstrap ─────────────────────────────────────────────────────────────
# Download lib/*.sh before anything else. SYSSET_FETCH_TOOL is set by get.sh;
# fall back to curl detection here in case get.bash is invoked directly.

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
for _f in net.sh os.sh str.sh json.sh github.sh ospkg.sh logging.sh checksum.sh graph.sh proc.sh devcontainer.sh jsonc.py; do
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
# shellcheck source=lib/str.sh
. "${_lib_dir}/str.sh"
# shellcheck source=lib/graph.sh
. "${_lib_dir}/graph.sh"
# shellcheck source=lib/proc.sh
. "${_lib_dir}/proc.sh"
# shellcheck source=lib/devcontainer.sh
. "${_lib_dir}/devcontainer.sh"

logging__setup
trap 'rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT

echo "↪️  Script entry: sysset installer" >&2

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
  Feature mode:   get.sh <feature>[@<feature-version>] [feature-opts...]
  Devcontainer:    get.sh <devcontainer.json[.jsonc]>

Options (see also header comment in get.bash):
  --logfile, --debug, --help
  --workspace-folder, --no-initialize-command, --initialize-command-dir, --lifecycle-command-dir
  --no-feature-lifecycle-command, --no-container-lifecycle-command, --compatible-prefix
  --no-lifecycle (feature mode: skip that feature's post-install hooks)

Version priority: per OCI :tag  >  SYSSET_VERSION  >  name vX.Y.Z suffix  >  latest
EOF
  exit "${1:-0}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
LOGFILE=""
_debug=false
_mode_arg=""
_WORKSPACE_CUSTOM=""
_NO_INIT_CMD=false
_INIT_CMD_DIR=""
_LIFE_CMD_DIR=""
_NO_FE_LIFE=()
_NO_CO_LIFE=()
_COMPAT_PREFIX=("ghcr.io/quantized8/sysset/")
_FEATURE_SKIP_LIFECYCLE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --logfile)
      shift
      [[ $# -eq 0 ]] && {
        echo "⛔ --logfile requires a value." >&2
        exit 1
      }
      LOGFILE="$1"
      shift
      ;;
    --debug)
      _debug=true
      shift
      ;;
    --help | -h) __usage__ ;;
    --workspace-folder)
      shift
      [[ $# -eq 0 ]] && {
        echo "⛔ --workspace-folder needs a value." >&2
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
        echo "⛔ --no-feature-lifecycle-command needs a value." >&2
        exit 1
      }
      _NO_FE_LIFE+=("$1")
      shift
      ;;
    --no-container-lifecycle-command)
      shift
      [[ $# -eq 0 ]] && {
        echo "⛔ --no-container-lifecycle-command needs a value." >&2
        exit 1
      }
      _NO_CO_LIFE+=("$1")
      shift
      ;;
    --compatible-prefix)
      shift
      [[ $# -eq 0 ]] && {
        echo "⛔ --compatible-prefix needs a value." >&2
        exit 1
      }
      _COMPAT_PREFIX+=("$1")
      shift
      ;;
    --no-lifecycle)
      _FEATURE_SKIP_LIFECYCLE=true
      shift
      ;;
    --*)
      echo "⛔ Unknown option: '${1}'" >&2
      exit 1
      ;;
    *)
      _mode_arg="$1"
      shift
      break
      ;;
  esac
done

[[ "$_debug" == true ]] && set -x

if [[ -z "$_mode_arg" ]]; then
  echo "⛔ No feature or manifest specified." >&2
  __usage__ 1
fi

# ── Mode detection ────────────────────────────────────────────────────────────
_mode=""
case "$_mode_arg" in
  *.json | *.jsonc) _mode="manifest" ;;
  *) _mode="feature" ;;
esac

# ── jq/yq helpers (required for manifest mode; installed on demand) ───────────

_install_jq() {
  echo "ℹ️  jq not found — installing via package manager." >&2
  ospkg__install jq
}

# ── Per-feature version resolution ──────────────────────────────────────────
# Resolves a feature-scoped version to its exact `<feature>/<X.Y.Z>` release
# tag. Supports partial/empty specs via github__resolve_version with
# --prefix '<feature>/' and --all (release tags fan out across all features,
# so per_page=100 is not enough).
_resolve_feature_tag() {
  # $1 = feature id, $2 = version spec (may be empty → latest)
  local _feature="$1" _spec="${2:-}"
  github__resolve_version "${SYSSET_REPO}" "$_spec" \
    --prefix "${_feature}/" --all
}

# ── Bundle manifest: fetch + parse ──────────────────────────────────────────
# Bundle-pinned mode fetches <bundle>/manifest.yaml once and caches it on disk.
# The manifest records {<feature>: <X.Y.Z>} per feature at bundle-cut time.
_BUNDLE_TAG=""           # Resolved bundle tag (e.g. v1.2.3); "" in rolling mode.
_BUNDLE_MANIFEST_FILE="" # Path to downloaded bundle manifest.yaml; "" if N/A.

# _resolve_bundle_tag <spec> — Resolve a bundle-version spec to its v<X.Y.Z> tag.
_resolve_bundle_tag() {
  local _spec="${1:-}"
  github__resolve_version "${SYSSET_REPO}" "$_spec" --prefix "v" --all
}

# _fetch_bundle_manifest <bundle-tag> <dest-file> — Download manifest.yaml from
# the bundle release.
_fetch_bundle_manifest() {
  local _tag="$1" _dest="$2"
  local _url="${SYSSET_RELEASE_BASE}/${_tag}/manifest.yaml"
  net__fetch_url_file "${_url}" "${_dest}" || return 1
  return 0
}

# _lookup_bundle_feature_version <manifest.yaml> <feature> — Print the feature's
# X.Y.Z version from the bundle manifest. Exits 1 if the feature is absent.
_lookup_bundle_feature_version() {
  local _manifest="$1" _feature="$2" _version=""
  if command -v yq > /dev/null 2>&1; then
    # shellcheck disable=SC2016  # $f is a yq variable (--arg), not a shell variable
    _version="$(yq -r --arg f "$_feature" '.features[$f] // ""' "$_manifest" 2> /dev/null)" || _version=""
  fi
  if [[ -z "${_version}" || "${_version}" == "null" ]] && command -v python3 > /dev/null 2>&1; then
    _version="$(python3 -c '
import sys
path, feat = sys.argv[1], sys.argv[2]
try:
    import yaml  # type: ignore
    with open(path, encoding="utf-8") as fp:
        data = yaml.safe_load(fp) or {}
except ImportError:
    data = {}
    current = None
    in_features = False
    with open(path, encoding="utf-8") as fp:
        for raw in fp:
            line = raw.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            if line.startswith("features:"):
                in_features = True
                continue
            if in_features:
                if line and not line[0].isspace():
                    in_features = False
                    continue
                stripped = line.strip()
                if ":" in stripped:
                    k, v = stripped.split(":", 1)
                    data.setdefault("features", {})[k.strip()] = v.strip().strip("\"\x27")
feats = (data or {}).get("features") or {}
v = feats.get(feat, "")
if isinstance(v, str):
    print(v)
' "$_manifest" "$_feature" 2> /dev/null)" || _version=""
  fi
  if [[ -z "${_version}" || "${_version}" == "null" ]]; then
    return 1
  fi
  printf '%s\n' "$_version"
}

# ── Shared tarball fetch + verify ────────────────────────────────────────────
# Downloads sysset-<feature>.tar.gz for a feature's <feature>/<X.Y.Z> tag and
# verifies its SHA-256 against the digest field from the GitHub Releases API.
# Best-effort: warns when the API omits the digest; fails on a mismatch.
_fetch_and_verify_tarball() {
  # $1 = feature id, $2 = resolved tag (<feature>/<X.Y.Z>), $3 = destination file
  local _feature="$1" _resolved="$2" _dest="$3"
  local _asset_name="sysset-${_feature}.tar.gz"
  github__fetch_release_asset_tarball "${SYSSET_REPO}" "${_resolved}" "${_asset_name}" "${_dest}" || return 1
  return 0
}

# ── Resolve (feature, spec) → tag ──────────────────────────────────────────
# Applies the priority rules:
#
#   1. If <spec> is non-empty, resolve <feature>/<spec> directly
#      (per-feature override; wins in every mode).
#   2. Else if bundle mode is active, look up the feature's version in the
#      bundle manifest; return <feature>/<version>.
#   3. Else (rolling mode), resolve the latest <feature>/<X.Y.Z> release.
#
# Stdout: the resolved <feature>/<X.Y.Z> tag.
_resolve_install_tag() {
  local _feature="$1" _spec="${2:-}" _version=""
  if [[ -n "$_spec" ]]; then
    echo "ℹ️  [${_feature}] Resolving per-feature version (spec: '${_spec}')..." >&2
    _resolve_feature_tag "$_feature" "$_spec"
    return $?
  fi
  if [[ -n "$_BUNDLE_TAG" ]]; then
    _version="$(_lookup_bundle_feature_version "$_BUNDLE_MANIFEST_FILE" "$_feature")" || {
      echo "⛔ [${_feature}] Feature not listed in bundle '${_BUNDLE_TAG}' manifest." >&2
      return 1
    }
    echo "ℹ️  [${_feature}] Using bundle ${_BUNDLE_TAG} → version '${_version}'." >&2
    printf '%s/%s\n' "$_feature" "$_version"
    return 0
  fi
  echo "ℹ️  [${_feature}] Resolving latest per-feature release..." >&2
  _resolve_feature_tag "$_feature" ""
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
    echo "⚠️  --no-feature-lifecycle-command '$_e' references a different feature (installed: '$_fid'); ignoring." >&2
  done
}

# _sysset_run_feature_lifecycle <staged-root> <fid> <cwd>
_sysset_run_feature_lifecycle() {
  local _root="${1-}" _fid="${2-}" _w="${3:-$PWD}" _ph _line _scope _sid _cmd
  local _df="${_root}/devcontainer-feature.json"
  [[ -f "$_df" ]] || {
    echo "ℹ️  No devcontainer-feature.json; skipping feature lifecycle" >&2
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
        echo "ℹ️  [${_sid}] skip feature ${_ph} (disabled)" >&2
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
  case "$_mode_arg" in
    *@*)
      _feature="${_mode_arg%%@*}"
      _feat_version_spec="${_mode_arg#*@}"
      ;;
    *)
      _feature="$_mode_arg"
      _feat_version_spec=""
      ;;
  esac

  if [[ -z "$_feat_version_spec" && -n "${SYSSET_VERSION:-}" ]]; then
    if ! _BUNDLE_TAG="$(_resolve_bundle_tag "${SYSSET_VERSION}")" || [[ -z "$_BUNDLE_TAG" ]]; then
      echo "⛔ Bad SYSSET_VERSION" >&2
      exit 1
    fi
    _BUNDLE_MANIFEST_FILE="$(mktemp)"
    trap 'rm -f "$_BUNDLE_MANIFEST_FILE"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
    _fetch_bundle_manifest "$_BUNDLE_TAG" "$_BUNDLE_MANIFEST_FILE" || exit 1
  fi

  if ! _RESOLVED="$(_resolve_install_tag "$_feature" "$_feat_version_spec")" || [[ -z "$_RESOLVED" ]]; then
    exit 1
  fi
  _tmpdir="$(mktemp -d)"
  trap 'rm -rf "$_lib_tmpdir" "$_tmpdir" ${_BUNDLE_MANIFEST_FILE:+"$_BUNDLE_MANIFEST_FILE"}; logging__cleanup' EXIT
  if ! _fetch_and_verify_tarball "$_feature" "$_RESOLVED" "${_tmpdir}/feature.tar.gz"; then
    exit 1
  fi
  tar -xzf "${_tmpdir}/feature.tar.gz" -C "$_tmpdir"
  sh "${_tmpdir}/install.sh" "$@"
  _wf="${_WORKSPACE_CUSTOM:-$PWD}"
  if [[ "$_FEATURE_SKIP_LIFECYCLE" != true ]]; then
    _lf="${_LIFE_CMD_DIR:-$_wf}"
    _sysset_run_feature_lifecycle "$_tmpdir" "$_feature" "$_lf" || exit 1
  fi
  echo "↩️  Script exit: sysset installer" >&2
  exit 0
fi

# ══ Devcontainer manifest mode ══════════════════════════════════════════
if [[ ! -f "$_mode_arg" ]]; then
  echo "⛔ Not found: $_mode_arg" >&2
  exit 1
fi
os__require_root
if ! command -v jq &> /dev/null; then
  _install_jq
fi

_DCJ="$(mktemp)"
# shellcheck disable=SC2064
trap 'rm -f "$_DCJ"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
devcontainer__parse_config "$_mode_arg" > "$_DCJ" || exit 1

_STAGED="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -rf "$_STAGED" "$_DCJ"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT

_WORK_ROOT="$(devcontainer__workspace_folder "$_mode_arg")"
[[ -n "$_WORKSPACE_CUSTOM" ]] && _WORK_ROOT="$_WORKSPACE_CUSTOM"

_BUNDLE_NAME_VER="$(devcontainer__name_version_suffix "$(jq -r '.name // ""' < "$_DCJ")")"
_bspec=""
if [[ -n "${SYSSET_VERSION:-}" ]]; then
  _bspec="${SYSSET_VERSION}"
elif [[ -n "$_BUNDLE_NAME_VER" ]]; then
  _bspec="${_BUNDLE_NAME_VER}"
fi
if [[ -n "$_bspec" ]]; then
  if ! _BUNDLE_TAG="$(_resolve_bundle_tag "${_bspec}")" || [[ -z "$_BUNDLE_TAG" ]]; then
    echo "⛔ Bundle tag not found for '$_bspec'" >&2
    exit 1
  fi
  _BUNDLE_MANIFEST_FILE="$(mktemp)"
  _fetch_bundle_manifest "$_BUNDLE_TAG" "$_BUNDLE_MANIFEST_FILE" || exit 1
fi

declare -A _KEY_OF=() _OPT_OF=() _TAG_OF=()
_IDS=()
while IFS=$'\t' read -r _id _k _tt; do
  [[ -z "$_id" ]] && continue
  _opt="$(jq -c --arg k "$_k" '(.features // {})[$k] // {}' < "$_DCJ")"
  _IDS+=("$_id")
  _KEY_OF["$_id"]="$_k"
  _OPT_OF["$_id"]="$_opt"
  _TAG_OF["$_id"]="$_tt"
done < <(devcontainer__iter_features "$_DCJ" "$_WORK_ROOT" "${_COMPAT_PREFIX[@]}")
((${#_IDS[@]})) || {
  echo "⛔ no features" >&2
  exit 1
}

# Stage tarballs (skip and record failures; continue with remaining features)
_failed=()
_OK_IDS=()
for _id in "${_IDS[@]}"; do
  mkdir -p "${_STAGED}/${_id}"
  if ! _rt="$(_resolve_install_tag "$_id" "${_TAG_OF[$_id]}")" || [[ -z "$_rt" ]]; then
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
    echo "⛔ missing devcontainer-feature.json in $_id" >&2
    _failed+=("$_id")
    continue
  fi
  _OK_IDS+=("$_id")
done
((${#_OK_IDS[@]})) || {
  echo "⛔ no features could be staged" >&2
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
  echo "⛔ failed to build ordering inputs" >&2
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
echo "ℹ️  order: ${_ORDER[*]}" >&2

if [[ "$_NO_INIT_CMD" != true ]]; then
  _iv="$(jq -c 'if (has("initializeCommand")|not) then null else .initializeCommand end' < "$_DCJ" 2> /dev/null || echo "null")"
  if [[ -n "$_iv" && "$_iv" != "null" ]]; then
    echo "⚠️  initializeCommand (host): trust this config" >&2
    (cd "${_INIT_CMD_DIR:-$_WORK_ROOT}" && printf '%s' "$_iv" | proc__run_command_form --cwd "${_INIT_CMD_DIR:-$_WORK_ROOT}") || exit 1
  fi
fi

_RU="$(jq -r '.remoteUser // ""' < "$_DCJ" 2> /dev/null | head -1)"
_CU="$(jq -r '.containerUser // ""' < "$_DCJ" 2> /dev/null | head -1)"
_EFF_USER="${_RU:-${_CU:-$USER}}"
_EFF_CUSER="${_CU:-$USER}"
_RU_HOME="$(devcontainer__user_home "$_EFF_USER" 2> /dev/null || true)"
_CU_HOME="$(devcontainer__user_home "$_EFF_CUSER" 2> /dev/null || true)"
[[ -z "$_RU_HOME" ]] && _RU_HOME="${HOME:-}"
[[ -z "$_CU_HOME" ]] && _CU_HOME="${HOME:-}"

_passed=()
for _id in "${_ORDER[@]}"; do
  _r2="$(_resolve_install_tag "$_id" "${_TAG_OF[$_id]}")" || {
    _failed+=("$_id")
    continue
  }
  _wdir="$(mktemp -d)"
  if ! _fetch_and_verify_tarball "$_id" "$_r2" "${_wdir}/a.tgz"; then
    _failed+=("$_id")
    rm -rf "$_wdir"
    continue
  fi
  tar -xzf "${_wdir}/a.tgz" -C "$_wdir"
  (
    if ! _sysset_options_to_env <<< "${_OPT_OF[$_id]-}"; then
      exit 1
    fi
    export _REMOTE_USER="${_EFF_USER}"
    export _CONTAINER_USER="${_EFF_CUSER}"
    export _REMOTE_USER_HOME="${_RU_HOME}"
    export _CONTAINER_USER_HOME="${_CU_HOME}"
    cd "$_wdir" || exit 1
    echo "ℹ️  [${_id}] running install.sh" >&2
    sh install.sh
  ) && _passed+=("$_id") || _failed+=("$_id")
  rm -rf "$_wdir"
done

_LCW="${_LIFE_CMD_DIR:-$_WORK_ROOT}"
_LIFE_USER="${_RU:-}"
for _ph in onCreateCommand updateContentCommand postCreateCommand postStartCommand postAttachCommand; do
  while IFS=$'\t' read -r _scope _sid _cmd; do
    [[ -z "$_scope" ]] && continue
    if [[ "$_scope" == feature ]]; then
      if _sysset_disabled_fe "$_sid" "$_ph" ""; then
        echo "ℹ️  [${_sid}] skip feature ${_ph} (disabled)" >&2
        continue
      fi
    else
      if _sysset_disabled_co "$_ph" ""; then
        echo "ℹ️  skip container ${_ph} (disabled)" >&2
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
  echo "⛔ failed: ${_failed[*]}" >&2
  exit 1
}
echo "↩️  Script exit: sysset installer" >&2
exit 0
