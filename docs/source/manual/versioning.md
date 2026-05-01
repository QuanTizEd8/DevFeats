# Versioning, Pinning, and Releases

SysSet uses per-feature versioning for installer resolution. CD also publishes bundle kits for offline/manual transfer. Installer bundle pinning is removed: `SYSSET_VERSION` and manifest `name` suffixes are ignored at runtime.

---

## Per-feature releases

Every feature is released under its own semver line:

- **Git tag:** `<feature-id>/<X.Y.Z>` - e.g. `install-pixi/1.2.3`
- **GitHub Release:** one per tag, with a single asset `sysset-<feature-id>.tar.gz`
- **OCI tags:** `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>:<major>`, `:<major>.<minor>`, `:<major>.<minor>.<patch>`

Semver semantics per feature: patch = behavior-preserving fix, minor = backwards-compatible addition, major = breaking change.

## Bundle releases

On every CD run that publishes at least one per-feature release, the pipeline also creates a **bundle release** under the tag `v<X.Y.Z>`. Each bundle ships **one** offline kit asset:

| Asset | Purpose |
|-------|---------|
| `sysset-v<X.Y.Z>.tar.gz` | Self-contained kit: `install.sh`, `install.bash`, `_lib/`, `manifest.json`, and digest-primary `features/` tree. |

`manifest.json` (schema version `2.0.0`) holds `version` (the bundle tag such as `v1.2.0`), provenance in `source`, a `features` map (`<feature-id>` -> semver), plus `refs` and `digests` for local-registry / offline resolution. A JSON Schema lives at [`schemas/kit-manifest.schema.json`](https://github.com/quantized8/sysset/blob/main/schemas/kit-manifest.schema.json).

---

## Pinning

Installer resolution is per-feature:

- **Rolling (default)** - feature resolves to latest.
- **Per-feature spec** - `feature:version` (CLI), or OCI `:tag`/`@sha256` in manifest keys.

### Per-feature version spec

A version spec can appear as `feature:version` on the CLI or as a `:tag`/`@sha256` on an OCI reference key:

| Spec | Resolves to |
|------|------------|
| *(empty)* or `latest` | Latest across all majors |
| `1` | Latest `1.x.y` |
| `1.2` | Latest `1.2.x` |
| `1.2.3` or `v1.2.3` | Exact version |

```sh
sh install.sh install-pixi:1              # latest 1.x.y
sh install.sh install-pixi:1.2            # latest 1.2.x
sh install.sh install-pixi:1.2.3          # exact 1.2.3
sh install.sh install-pixi:1.2 --version 0.66.0   # pin tarball, pass option through
```

In manifest mode, the `features[key]` value is an options object for that feature.
For example, `features[key].version` is an option named `version` passed to the
feature installer; it is not the artifact selector. Artifact selection is
driven by the key itself (`:tag` or `@sha256`).

The `:spec` suffix only affects *which* tarball is downloaded; all CLI flags after the feature ID are forwarded to the installer unchanged.

### Priority order

When more than one per-feature mechanism applies, the highest priority wins:

```text
OCI per-feature tag  (:tag on the key, or feature:version on the CLI)
        ↓
Latest per-feature release  (rolling)
```

---

## CLI reference

`install.sh` forwards every argument to `install.bash`, so both share the same CLI.

```text
Feature mode:   install.sh <feature>[:<spec>] [feature-opts...]
Manifest mode:  install.sh <devcontainer.json[.jsonc]>
```

| Flag | Description |
|------|-------------|
| `--log_level <level>` | Set verbosity: `silent`, `error`, `warn`, `info`, `debug`, `trace`. `trace` enables `bash -x` inside the feature installer. |
| `--log_file <path>` | Append captured output to this file on exit. Secrets detected via `GITHUB_TOKEN` are redacted. |
| `--help`, `-h` | Print embedded usage and exit. |
| `--workspace-folder <path>` | Default CWD for lifecycle commands. |
| `--no-initialize-command` | Manifest mode: skip `initializeCommand` entirely. |
| `--initialize-command-dir <path>` | Manifest mode: CWD for `initializeCommand`. |
| `--lifecycle-command-dir <path>` | CWD for all lifecycle commands other than `initializeCommand`. |
| `--no-feature-lifecycle-command <pattern>` | Repeatable. Disable per-feature lifecycle commands using the [disable grammar](manifests.md#disabling-lifecycle-commands). |
| `--no-container-lifecycle-command <pattern>` | Repeatable. Disable container-level lifecycle commands using the same grammar. |
| `--no-lifecycle` | Feature mode only: skip the installed feature's lifecycle hooks. |
| `--local-registry <path>` | Registry root containing `manifest.json` and `features/`. Default: directory of the resolved `install.bash`, or `SYSSET_LOCAL_REGISTRY`. |
| `--download-only` | Fetch features into the local registry and update `manifest.json`; do not run installers. |
| `--report-file <path>` | With `--download-only`, write a JSON summary of successes and failures. |

---

## Environment variables

| Variable | Description |
|----------|-------------|
| `SYSSET_LOCAL_REGISTRY` | Directory containing the offline kit (`manifest.json`, `features/`, ...). Overrides the default registry root (the directory of `install.bash`). |
| `SYSSET_RAW_BASE` | Raw GitHub base for `install.bash` and `lib/*.sh`. Default: `https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main`. Override to use a fork, a branch, or a local mirror. |
| `SYSSET_FETCH_TOOL` | Force `curl` or `wget`. Auto-detected when unset. |
| `LOG_FILE` | Append the installer's output to this file on exit. Equivalent to `--log_file`. Also honored by individual features. |
| `GITHUB_TOKEN` *(optional)* | Authenticate GitHub API calls; always masked in captured output. |

---

## Release artifacts

### Per-feature release

| Item | Value |
|------|-------|
| Git tag | `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`) |
| GitHub Release | One per tag |
| Asset | `sysset-<feature-id>.tar.gz` |
| Download URL | `https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/<feature-id>/<X.Y.Z>/sysset-<feature-id>.tar.gz` |
| OCI image | `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>` |
| OCI tags | `:<major>`, `:<major>.<minor>`, `:<major>.<minor>.<patch>` |

### Bundle release

| Item | Value |
|------|-------|
| Git tag | `v<X.Y.Z>` |
| GitHub Release | Marked `latest` on the repository |
| Asset | `sysset-v<X.Y.Z>.tar.gz` - offline kit (installers + `manifest.json` + digest layout) |
| Download URL | `https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/v<X.Y.Z>/sysset-v<X.Y.Z>.tar.gz` |

---

## Offline and air-gapped installs

The usual approach is to **extract the bundle kit** `sysset-v<X.Y.Z>.tar.gz`, run `install.sh` or `install.bash` from that directory (or set `SYSSET_LOCAL_REGISTRY` to the extracted root), and use explicit per-feature specs where deterministic resolution is required. For mirrors, `--download-only` pre-seeding, digest / registry behavior, and bootstrap without network, see the dedicated guide: {doc}`offline`.
