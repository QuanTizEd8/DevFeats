# Versioning, Pinning, and Releases

SysSet uses a two-level versioning scheme: **each feature is versioned independently** (the artifact you pin when you want to lock a single tool), and every CD run also publishes a **bundle release** (the snapshot you pin when you want a reproducible set of tools across your environment).

---

## Per-feature releases

Every feature is released under its own semver line:

- **Git tag:** `<feature-id>/<X.Y.Z>` — e.g. `install-pixi/1.2.3`
- **GitHub Release:** one per tag, with a single asset `sysset-<feature-id>.tar.gz`
- **OCI tags:** `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>:<major>`, `:<major>.<minor>`, `:<major>.<minor>.<patch>`

Semver semantics per feature: patch = behavior-preserving fix, minor = backwards-compatible addition, major = breaking change.

## Bundle releases

On every CD run that publishes at least one per-feature release, the pipeline also creates a **bundle release** under the tag `v<X.Y.Z>`. Each bundle ships **one** offline kit asset:

| Asset | Purpose |
|-------|---------|
| `sysset-v<X.Y.Z>.tar.gz` | Self-contained kit: `install.sh`, `install.bash`, `_lib/`, `manifest.json`, and digest-primary `features/` tree. The filename uses the **same** `v`-prefixed bundle tag as the GitHub Release (for `v1.2.0`, the file is `sysset-v1.2.0.tar.gz`), so one variable can build both the release path and the asset name. |

`manifest.json` (schema version `2.0.0`) holds `version` (the bundle tag such as `v1.2.0`), provenance in `source`, a `features` map (`<feature-id>` → semver) for bundle pinning, plus `refs` and `digests` for local-registry / offline resolution. A JSON Schema lives at [`schemas/kit-manifest.schema.json`](https://github.com/quantized8/sysset/blob/main/schemas/kit-manifest.schema.json).

:::{dropdown} Example `manifest.json` (truncated)

```json
{
  "schemaVersion": "2.0.0",
  "version": "v1.2.0",
  "generatedAt": "2026-04-27T12:00:00Z",
  "source": { "repo": "quantized8/sysset", "commit": "3f7a…" },
  "features": {
    "install-fonts": "0.1.0",
    "install-pixi": "1.3.0",
    "install-shell": "0.2.0"
  },
  "refs": { "ghcr.io/quantized8/sysset/install-pixi:1.3.0": "sha256:…" },
  "digests": { "sha256:…": { "relativePath": "features/…", "checksums": { } } }
}
```
:::

---

## Pinning

Three orthogonal pinning mechanisms let you choose the right trade-off between reproducibility and flexibility. They can be freely combined; conflicts are resolved by a well-defined priority.

::::{grid} 1 1 3 3
:gutter: 2

:::{grid-item-card} Rolling (no pin)
Every feature resolves to its latest per-feature release. Good for dev loops; avoid for production or archives.
:::

:::{grid-item-card} Per-feature (`:spec`)
Pin one feature to a specific version line (`feature:version`). Good for hotfixes and bisects.
:::

:::{grid-item-card} Bundle (`SYSSET_VERSION`)
Pin **every** feature to the versions inside a specific bundle release. Good for reproducible snapshots and air-gapped environments.
:::
::::

### Per-feature version spec

A version spec can appear as `feature:version` on the CLI, as a `:tag` on an OCI reference, or as a version value in a manifest:

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

The `:spec` suffix only affects *which* tarball is downloaded; all CLI flags after the feature ID are forwarded to the installer unchanged.

### Bundle pinning

Set `SYSSET_VERSION`, or add a `v<X>.<Y>.<Z>` suffix to the manifest's `name` field, to pin the bundle for the whole run. `install.bash` downloads `sysset-v<X.Y.Z>.tar.gz` for that bundle tag and reads `manifest.json` from it (or uses `manifest.json` next to the running installer when you use an extracted kit), then resolves each feature to the version listed in `features`.

```sh
# All features pinned to bundle v1.2.0
SYSSET_VERSION=v1.2.0 sh install.sh install-pixi install-shell

# Partial specs work too — resolved against bundle tags
SYSSET_VERSION=v1     sh install.sh my-setup.jsonc
SYSSET_VERSION=latest sh install.sh my-setup.jsonc
```

In a manifest, the equivalent pin is a version suffix on `name`:

```jsonc
{ "name": "my env v1.2.0", "features": { /* … */ } }
```

### Priority order

When more than one pinning mechanism applies, the highest priority wins:

```text
OCI per-feature tag  (:tag  on the key, or  feature:version  on the CLI)
        ↓
SYSSET_VERSION  or  v<X>.<Y>.<Z> in manifest name  (bundle)
        ↓
Latest per-feature release  (rolling)
```

A per-feature override always wins over a bundle pin — useful for taking a hotfix on one feature without abandoning the pinned set for the rest:

```sh
# Everything at v1.2.0, except install-pixi which rolls to latest 1.4.x
SYSSET_VERSION=v1.2.0 sh install.sh install-pixi:1.4 install-shell
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
| `--compatible-prefix <oci-prefix>` | Repeatable. OCI prefixes accepted in `features[…]`. Defaults to `ghcr.io/|{{github_user}}|/|{{github_repo}}|/`. Unknown prefixes are skipped with a warning. |
| `--no-lifecycle` | Feature mode only: skip the installed feature's lifecycle hooks. |
| `--local-registry <path>` | Registry root containing `manifest.json` and `features/`. Default: directory of the resolved `install.bash`, or `SYSSET_LOCAL_REGISTRY`. |
| `--download-only` | Fetch features into the local registry and update `manifest.json`; do not run installers. |
| `--report-file <path>` | With `--download-only`, write a JSON summary of successes and failures. |

---

## Environment variables

| Variable | Description |
|----------|-------------|
| `SYSSET_VERSION` | Bundle pin. Accepts: `""`, `latest`, `1`, `1.2`, `v1.2.3`, `1.2.3`. Per-feature `:spec` overrides still win. Equivalent to a `v*.*.*` suffix on the manifest's `name`. |
| `SYSSET_LOCAL_REGISTRY` | Directory containing the offline kit (`manifest.json`, `features/`, …). Overrides the default registry root (the directory of `install.bash`). |
| `SYSSET_BASE_URL` | GitHub Releases base URL. Default: `https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download`. Per-feature URLs: `<base>/<feature-id>/<X.Y.Z>/sysset-<feature-id>.tar.gz`. Bundle kit: `<base>/v<X.Y.Z>/sysset-v<X.Y.Z>.tar.gz`. Override for mirrors, including `file://` paths. |
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
| Asset | `sysset-v<X.Y.Z>.tar.gz` — offline kit (installers + `manifest.json` + digest layout) |
| Download URL | `https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/v<X.Y.Z>/sysset-v<X.Y.Z>.tar.gz` |

---

## Offline and air-gapped installs

The usual approach is to **extract the bundle kit** `sysset-v<X.Y.Z>.tar.gz`, run `install.sh` or `install.bash` from that directory (or set `SYSSET_LOCAL_REGISTRY` to the extracted root), and set `SYSSET_VERSION` so versions resolve from the embedded `manifest.json`. For mirrors, `--download-only` pre-seeding, digest / registry behavior, and bootstrap without network, see the dedicated guide: {doc}`offline`.

---

## Logs, diagnostics, and recovery

Every feature goes through the same logging pipeline, making failures easy to triage:

- **Emoji markers** — a consistent vocabulary: `↪️` entry, `ℹ️` info, `📩` input read, `📦` install, `⚠️` warning, `⛔`/`❌` error, `↩️` exit. Grep for `⛔`/`❌` to jump straight to failures.
- **`--log_file <path>`** — captures the full `tee`d output; append-safe across features in the same run.
- **`--log_level trace`** — enables `bash -x` inside generated feature installers; combine with `--log_file` to capture the trace.
- **Partial failures** — in manifest mode, `install.bash` attempts every feature and exits non-zero if any failed, naming them at the end. A feature whose hard dependencies failed is skipped.
- **Re-runs are idempotent** — installers check for already-done work and skip it, so you can rerun after fixing an environment issue without uninstalling first.
