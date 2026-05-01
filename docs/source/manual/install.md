# Installation Guide

SysSet features are available through two parallel channels: **Dev Container Features** (OCI packages on GHCR) and **standalone installers** (tarballs on GitHub Releases). Both are built from the same source on every release; only the invocation mechanism differs.

---

## Dev Container Features

Each SysSet feature is published to GHCR under `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>`. Add any combination of features to your `.devcontainer/devcontainer.json`; the Dev Containers tooling fetches, orders, and installs them automatically on build.

```jsonc
{
  "image": "ubuntu:24.04",
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user:0":    { "username": "dev" },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell:0": {
      "ohmyzsh_theme":   "romkatv/powerlevel10k",
      "set_user_shells": "zsh"
    },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi:0":  {}
  },
  "remoteUser": "dev"
}
```

### Tag pinning

Every feature publishes three OCI tags per release — `:<major>`, `:<major>.<minor>`, and `:<major>.<minor>.<patch>` — so you can pin at whatever precision you need:

| Tag | Resolves to | Use when |
|-----|------------|----------|
| `:0` | Latest `0.x.y` | API stability with transparent patch updates |
| `:0.1` | Latest `0.1.x` | Locked to a minor line |
| `:0.1.3` | Exact `0.1.3` | Fully reproducible build |
| *(no tag)* | Latest, any version | Experiments only — not recommended |

---

## Standalone: `install.sh`

`install.sh` is a small POSIX `sh` bootstrap at the root of this repository. It locates (or installs) bash ≥ 4, downloads the full `install.bash` implementation, and hands off execution — forwarding every argument verbatim.

Download it once and run it as many times as you like, or pipe it directly for a one-shot install:

```sh
# One-shot
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh \
  | sh -s -- install-pixi

# Download once, reuse
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh -o install.sh
sh install.sh install-shell --set_user_shells zsh
sh install.sh setup-user    --username dev
```

`install.sh` operates in one of two modes depending on the first argument.

### Feature mode — install one feature

Give `install.sh` a feature ID, optionally with a `:<version>` suffix. Every argument after the feature ID is forwarded to the feature's `install.bash` as CLI flags:

```sh
# Latest version
sh install.sh install-pixi

# With options
sh install.sh install-pixi --version 0.66.0

# Array-type option: repeat the flag for each value
sh install.sh install-fonts --nerd_fonts Meslo --nerd_fonts FiraCode

# Pin to a specific version line
sh install.sh install-pixi:1.2.3 --version 0.66.0
```

### Manifest mode — install multiple features

If the first argument ends in `.json` or `.jsonc`, `install.sh` treats it as a devcontainer manifest and installs every entry under `features`:

```sh
sudo sh install.sh .devcontainer/devcontainer.jsonc
```

`install.sh` parses the file, resolves each feature independently (OCI refs / per-feature specs), fetches each feature artifact, orders them by dependency, and runs each installer with the corresponding options injected as environment variables. See {doc}`manifests` for full details on the manifest format, install ordering, and lifecycle commands.

### Lockfile modes

`install.bash` supports optional lockfiles for reproducible OCI installs:

- `--lockfile <path>` writes resolved refs after a successful manifest install.
- `--frozen-lockfile <path>` requires an existing lockfile and installs exactly the listed refs.

The lockfile records the feature key and resolved immutable ref used by the installer.

### OCI authentication inputs

For private registries, provide credentials via:

- `SYSSET_OCI_AUTH` as comma-separated `registry|username|token` entries
- `SYSSET_OCI_AUTH_FILE` pointing to a file containing the same value format

Example:

```sh
export SYSSET_OCI_AUTH="ghcr.io|USERNAME|ghp_xxx,registry.example.com|robot|s3cr3t"
sudo sh install.sh .devcontainer/devcontainer.json --lockfile .devcontainer/devcontainer-lock.json
```

### OCI integrity validation

For OCI feature pulls, `install.bash` validates two layers before execution:

- **Artifact shape** — pulled archive must contain `install.sh` and `devcontainer-feature.json`
- **Layer digest** — when registry manifest metadata provides a compatible feature layer digest, the pulled archive hash must match that digest

Digest-pinned refs (`@sha256:...`) additionally prefer the local validated registry cache when available.

### Directly running a per-feature tarball

Every release ships a self-contained tarball per feature. It contains the bootstrap, the real installer, and a private copy of the shared library — it runs entirely offline once downloaded:

```sh
curl -fsSL https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/install-pixi/1.2.3/sysset-install-pixi.tar.gz \
  | tar xz -C /tmp/pixi
sudo sh /tmp/pixi/install.sh --version 0.66.0
```

:::{dropdown} What's inside a per-feature tarball?

```text
sysset-<feature-id>.tar.gz
├── install.sh                  ← POSIX sh bootstrap (ensures bash ≥ 4, execs install.bash)
├── install.bash                ← Real bash ≥ 4 installer
├── devcontainer-feature.json   ← Generated from metadata.yaml
├── _lib/                       ← Full copy of the shared bash library (no network needed)
├── dependencies/               ← OS package manifest (when the feature has one)
└── files/                      ← Supplementary files (when the feature has any)
```

The bootstrap (`install.sh`) handles bash ≥ 4 resolution the same way the top-level `install.sh` does. You can safely inspect every file in the tarball before running it.
:::
