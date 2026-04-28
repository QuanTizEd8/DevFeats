# User Guide



1. **One source of truth per feature.** Every feature has a single authoritative implementation, a single option schema, and a single release pipeline. All distribution channels are built from the same bits on every release, so they never drift.
2. **Cross-platform by default.** Every installer works on Debian/Ubuntu, RHEL/Fedora, Alpine, Arch, openSUSE, and macOS. Package-manager detection, user resolution, and shell-integration are all handled internally, so you do not pick a variant per OS.
3. **Dual-mode installers.** Each installer accepts options both as environment variables (the way dev container tooling injects them) and as CLI flags (the way a human or script invokes them). This is what lets the same installer run under `devcontainer up`, under SysSet's installer, and as a pipe-to-`sh` one-liner — with identical behavior.





## Quickstart

The most straightforward way to install a feature is to download the SysSet installer script at `https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh` (e.g. using `curl`) and execute it with a POSIX-compliant shell (e.g. `sh`), passing the feature ID and any options as arguments:

```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh | sh -s -- <feature-id>[:<version>] [--options]
```

For example, to install the latest version of the `install-shell` feature with default options:

```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh | sh -s -- install-shell
```
Or to install a specific version (e.g. `0.1.0`) and override a default option (e.g. set `ohmyzsh_theme` to `romkatv/powerlevel10k`):
```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh | sh -s -- install-shell:0.1.0 --ohmyzsh_theme romkatv/powerlevel10k
```

:::{admonition} Download once and reuse
:class: tip dropdown

The above examples download the `install.sh` script and pipe it directly to the shell for a one-shot install. For multiple installs, it's more efficient to download the script once and run it multiple times to install different features:

```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh -o install.sh
sh install.sh setup-user --username johndoe
sh install.sh install-shell --ohmyzsh_theme romkatv/powerlevel10k --install_direnv true
```
:::

While the above method can be used to install multiple features, for a more complex environment with many features and options, it is more convenient to declare the whole setup in a JSON file:

```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user": {
      "username": "johndoe"
    },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell": {
      "ohmyzsh_theme": "romkatv/powerlevel10k",
      "install_direnv": true
    }
  }
}
```

The installer script can take this file as an argument and install all listed features in one go, with correct ordering and dependency resolution:

```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh | sh -s -- path/to/file.json
```

The installer script can be used universally on physical machines (e.g. to set up a new laptop or update a PC), virtual machines (e.g. to set up a cloud VM, such as a GitHub Actions runner, for a CI workflow), and containers (e.g. as a RUN instruction in a Dockerfile or executed inside a running container). Additionally, all SysSet features are fully compliant with the [Development Container Specification](https://containers.dev/implementors/spec/) and can be used as drop-in features in any `devcontainer.json` file, where they are automatically installed by compliant tools like VS Code Dev Containers and GitHub Codespaces.





:::::{tab-set}

::::{tab-item} Dev container feature

Add features to `.devcontainer/devcontainer.json` under `features` and rebuild the container. The major-version tag pins the API while still receiving patch updates.

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user:0":    { "username": "dev" },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell:0": {
      "set_user_shells": "zsh",
      "ohmyzsh_theme":   "romkatv/powerlevel10k"
    },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi:0":  {}
  },
  "remoteUser": "dev"
}
```

Open the project in VS Code → **Reopen in Container**, or run:

```sh
devcontainer up --workspace-folder .
```
::::

::::{tab-item} Standalone (single feature)

Pipe `install.sh` to your shell to install one feature. Arguments after `sh -s --` are forwarded to the feature installer.

```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh \
  | sh -s -- install-pixi --version 0.66.0
```

Or download once and run multiple times:

```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh -o install.sh
sh install.sh install-shell --set_user_shells zsh
sh install.sh setup-user    --username dev
```
::::

::::{tab-item} Standalone (manifest)

Write a `devcontainer.json` and hand it to `install.sh`. It installs all listed features on the host in dependency order — no container required.

```sh
curl -fsSL https://raw.githubusercontent.com/|{{github_user}}|/|{{github_repo}}|/main/install.sh -o install.sh
sudo sh install.sh .devcontainer/my-setup.jsonc
```

Where `my-setup.jsonc` is:

```jsonc
{
  "name": "my env v1.2.0",
  "remoteUser": "dev",
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user":    { "username": "dev" },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell": {
      "set_user_shells": "zsh",
      "ohmyzsh_theme":   "romkatv/powerlevel10k"
    },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi":  {}
  }
}
```
::::

:::::

:::{note}
`sudo` is required when a feature writes to system directories (almost all of them do). Dev container tooling already runs feature installs as root; with `install.sh` you need to supply the privilege yourself.
:::

---

## Prerequisites

**For standalone installs (`install.sh`):**

- `curl` or `wget` — for downloads (auto-detected; override with `SYSSET_FETCH_TOOL`).
- `bash` ≥ 4 — installed automatically via the detected system package manager if absent. Supports `apt-get`, `apk`, `dnf`, `microdnf`, `yum`, `zypper`, `pacman`, Homebrew, MacPorts, and Nix.
- Root or `sudo` — required by most features, as they write to system locations.

**For dev container features:**

- A Dev Containers spec-compliant tool: VS Code Dev Containers, GitHub Codespaces, `@devcontainers/cli`, or similar.

---

---

## In this guide

| Section | What you'll find |
|---------|-----------------|
| {doc}`installation` | All installation methods in detail: dev container features, standalone, manifest mode, and direct tarball |
| {doc}`options` | Feature options: CLI flags vs environment variables, shared options, and the array type |
| {doc}`manifests` | Manifest mode: `devcontainer.json` parity, install ordering, and lifecycle commands |
| {doc}`versioning` | Versioning and pinning, bundle releases, CLI reference, and diagnostics |
| {doc}`offline` | Offline kit, local registry, download-only pre-seeding, mirrors, and air-gapped bootstrap |
