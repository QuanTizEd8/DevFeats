# User Guide

This guide covers everything you need to install and use SysSet features: installation methods, options, manifest mode, versioning and pinning, and advanced topics. For the specifics of each individual feature (options, defaults, behavior), see the per-feature pages under {doc}`/features`.

---

## Quickstart

Pick the tab that matches how you want to use SysSet. Each example is complete and immediately runnable.

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

## Design principles

SysSet treats system setup the way modern application runtimes treat deployments: as a **declarative, reproducible, portable** operation. Three commitments follow from that:

1. **One source of truth per feature.** Every feature has a single authoritative implementation (`features/<id>/install.bash`), a single option schema (`metadata.yaml`), and a single release pipeline. Both distribution channels are built from the same bits on every push, so they never drift.
2. **Cross-platform by default.** Every installer works on Debian/Ubuntu, RHEL/Fedora, Alpine, Arch, openSUSE, and macOS. Package-manager detection, user resolution, and shell-integration are all handled by a shared bash library — you do not pick a variant per OS.
3. **Dual-mode installers.** Each `install.bash` accepts options both as environment variables (the way dev container tooling injects them) and as CLI flags (the way a human or script invokes them). This is what lets the same installer run under `devcontainer up`, under SysSet's manifest runner, and as a pipe-to-`sh` one-liner — with identical behavior.

---

## In this guide

| Section | What you'll find |
|---------|-----------------|
| {doc}`installation` | All installation methods in detail: dev container features, standalone, manifest mode, and direct tarball |
| {doc}`options` | Feature options: CLI flags vs environment variables, shared options, and the array type |
| {doc}`manifests` | Manifest mode: `devcontainer.json` parity, install ordering, and lifecycle commands |
| {doc}`versioning` | Versioning and pinning, bundle releases, offline installs, CLI reference, and diagnostics |
