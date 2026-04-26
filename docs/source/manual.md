# User Guide


This page is the user guide for everything that is *not* specific to an individual feature: what SysSet is, how it is distributed and versioned, how to install one or many features via every supported entry point, how options and inputs work, what parts of `devcontainer.json` are honored by the standalone installer, and how to pin, mirror, or air-gap a release. For the specifics of each feature (options, defaults, behavior), see the per-feature pages under {doc}`/features`.

Features are distributed as both  and **self-contained/bundled installers**,
published to [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
and



:::{tip}
:class: dropdown
**In a hurry?** Jump to the [Quickstart](#quickstart) section below and pick the tab that matches how you want to install — as a dev container feature, as a one-shot standalone command, or from a multi-feature manifest.
:::

---

## Philosophy

SysSet treats system setup the way modern application runtimes treat deployments: as a **declarative, reproducible, portable** operation. A feature should produce the same result whether it runs inside a dev container during image build, inside a fresh VM provisioned by a CI job, or on a developer's laptop — and it should let you pin a snapshot, inspect it, mirror it, and replay it later.

Three concrete commitments come out of that:

1. **One source of truth per feature.** Every feature has a single authoritative implementation (`features/<id>/install.bash`), a single option schema (`metadata.yaml`), and a single release pipeline. Both distribution channels (OCI feature + standalone tarball) are built from the same bits on every push, so the two channels never drift.
2. **Cross-platform by default.** Every installer is written to work on Debian/Ubuntu, RHEL/Fedora, Alpine, Arch, openSUSE, and macOS, with the package-manager detection, user resolution, and shell-integration knobs all handled by a shared bash library that ships inside each feature tarball. You do not need to pick a feature variant per OS.
3. **Dual-mode installers.** Each `install.bash` accepts its options both as environment variables (the way dev container tooling injects them) and as CLI flags (the way a human or a shell script invokes them). That is what lets the same installer run under `devcontainer up`, under `sysset's` own manifest runner, and as a pipe-to-`sh` one-liner — with identical behavior.

---

## Distribution channels

SysSet features are published in two parallel forms. They are built from the same commit in the same CI run and carry the same version, so you can freely mix them in the same workflow.

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} Dev Container features (OCI, GHCR)
:class-title: sd-text-center

Referenced from a `devcontainer.json` as `ghcr.io/quantized8/sysset/<feature-id>:<tag>`. Consumed by the Dev Containers spec tooling — VS Code Dev Containers, GitHub Codespaces, the `@devcontainers/cli`, and every other spec-compliant builder. Use this when you are building a container.
:::

:::{grid-item-card} Standalone installers (GitHub Releases)
:class-title: sd-text-center

Self-contained per-feature tarballs plus an accumulator bundle. Driven by the `get.sh` / `get.bash` installer in this repo, or run straight from a downloaded tarball. Use this on VMs, CI runners, WSL2, remote hosts, and any environment where you do not want (or cannot use) a dev container toolchain.
:::
::::

Because both channels are produced from the same source, the *options* and *behavior* of a feature are identical across them. Only the **invocation mechanism** differs — the env-var / CLI-flag mapping is the same in either case.

---

## Quickstart

Pick the tab that matches how you want to install. Each tab is a complete, runnable example; the rest of the guide expands on the details.

:::::{tab-set}

::::{tab-item} As a dev container feature

Add any feature to `.devcontainer/devcontainer.json` under `features` and rebuild the container. The major-version tag pins the API while still receiving patch updates.

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0":    { "username": "dev" },
    "ghcr.io/quantized8/sysset/install-shell:0": {
      "set_user_shells": "zsh",
      "ohmyzsh_theme":   "romkatv/powerlevel10k"
    },
    "ghcr.io/quantized8/sysset/install-pixi:0":  {}
  },
  "remoteUser": "dev"
}
```

Open the project in VS Code → **Reopen in Container**, or run:

```sh
devcontainer up --workspace-folder .
```
::::

::::{tab-item} As a one-shot standalone install

Pipe `get.sh` into your shell to install a single feature. All arguments after `sh -s --` are forwarded to the feature's installer.

```sh
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh \
  | sh -s -- install-pixi --version 0.66.0
```

Or download `get.sh` once and run it as many times as you like:

```sh
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh -o get.sh
sh get.sh install-shell --set_user_shells zsh
sh get.sh setup-user    --username dev
```
::::

::::{tab-item} From a multi-feature manifest

Write a `devcontainer.json` (or `.jsonc`) and hand it to `get.sh`. It installs the listed features in dependency order on the host — no container required.

```sh
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh -o get.sh
sudo sh get.sh .devcontainer/my-setup.jsonc
```

Where `my-setup.jsonc` is:

```jsonc
{
  "name": "my env v1.2.0",
  "remoteUser": "dev",
  "features": {
    "ghcr.io/quantized8/sysset/setup-user":    { "username": "dev" },
    "ghcr.io/quantized8/sysset/install-shell": {
      "set_user_shells": "zsh",
      "ohmyzsh_theme":   "romkatv/powerlevel10k"
    },
    "ghcr.io/quantized8/sysset/install-pixi":  {}
  }
}
```
::::

:::::

:::{note}
`sudo` is required when a feature writes to system directories (almost all of them do). On a devcontainer, the spec tooling already runs feature installs as root; with `get.sh` you need to provide the privilege yourself.
:::

---

## Installing as a dev container feature

Each SysSet feature is published to GHCR under `ghcr.io/quantized8/sysset/<feature-id>`, with OCI tags for every released version. Add any combination of features to your `.devcontainer/devcontainer.json` — the Dev Containers tooling will fetch, order, and install them for you on build.

```jsonc
{
  "image": "ubuntu:24.04",
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0":    { "username": "dev" },
    "ghcr.io/quantized8/sysset/install-shell:0": {
      "ohmyzsh_theme":   "romkatv/powerlevel10k",
      "set_user_shells": "zsh"
    },
    "ghcr.io/quantized8/sysset/install-pixi:0":  {}
  },
  "remoteUser": "dev"
}
```

### Tag pinning

Every feature publishes three OCI tags per release — `:<major>`, `:<major>.<minor>`, and `:<major>.<minor>.<patch>` — so you can pin at whatever precision you want:

| Tag    | Resolves to                    | Use when                                              |
|--------|--------------------------------|-------------------------------------------------------|
| `:0`   | Latest `0.x.y`                 | You want API stability but transparent patch updates. |
| `:0.1` | Latest `0.1.x`                 | You want to lock a minor line.                        |
| `:0.1.3` | Exact `0.1.3`                | You need a fully reproducible build.                  |
| *(no tag)* | Latest, any version        | Not recommended outside of experiments.               |

See [Versioning and pinning](#versioning-and-pinning) below for how this interacts with the bundle-level pin when you use `get.sh` in manifest mode.

---

## Installing with `get.sh` (standalone)

`get.sh` is a tiny POSIX `sh` bootstrap committed at the root of this repo. It locates (or installs) bash ≥ 4, downloads the full `get.bash` implementation, and hands off execution — forwarding every argument verbatim. It operates in one of two modes depending on the first positional argument.

:::{card} Requirements
:class-card: sd-border-0

- **`curl` or `wget`** for downloads (auto-detected; override with `SYSSET_FETCH_TOOL`).
- **`bash` ≥ 4**, installed automatically via the detected system package manager if absent (supports `apt-get`, `apk`, `dnf`, `microdnf`, `yum`, `zypper`, `pacman`, Homebrew, MacPorts, and Nix).
- **Root or `sudo`** — required by most features, as they write to system locations.
:::

### Feature mode — install one feature

The fastest path: give `get.sh` a feature ID and optionally a `@<version>` suffix. Everything after the feature ID is forwarded to the feature's `install.bash` as CLI flags.

```sh
# One-shot, latest version
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh \
  | sh -s -- install-pixi

# Pass options to the feature installer
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh \
  | sh -s -- install-pixi --version 0.66.0

# Download once, run many times
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh -o get.sh
sh get.sh install-shell --set_user_shells zsh --ohmyzsh_theme romkatv/powerlevel10k
sh get.sh install-fonts --nerd_fonts Meslo --nerd_fonts FiraCode
sh get.sh setup-user    --username dev
```

:::{note}
**Array options** such as `install-fonts`' `nerd_fonts` take multiple values by **repeating the flag** (`--nerd_fonts Meslo --nerd_fonts FiraCode`). See [Common option behaviors](#common-option-behaviors) for the full rules.
:::

### Manifest mode — install multiple features

If the first argument ends in `.json` or `.jsonc`, `get.sh` treats it as a devcontainer manifest (see the [manifest-mode section below](#manifest-mode-devcontainer-json-parity)) and installs every entry under `features`:

```sh
sudo sh get.sh .devcontainer/devcontainer.jsonc
```

`get.sh` parses the file, resolves per-feature tags and/or a bundle pin, fetches every feature's tarball, orders them using the combined hard/soft dependency graph, and runs each `install.sh` with the corresponding options injected as environment variables. Lifecycle commands (`initializeCommand`, `onCreateCommand`, …) are honored, on the host — see [Lifecycle commands](#lifecycle-commands).

### Directly running a per-feature tarball

Every release ships a self-contained tarball per feature. It contains the bootstrap, the real installer, and a private copy of the shared library, so it runs entirely offline once downloaded:

```sh
curl -fsSL https://github.com/quantized8/sysset/releases/download/install-pixi/1.2.3/sysset-install-pixi.tar.gz \
  | tar xz -C /tmp/pixi
sudo sh /tmp/pixi/install.sh --version 0.66.0
```

:::{dropdown} What's inside a per-feature tarball?

```text
sysset-<feature-id>.tar.gz
├── install.sh                  ← POSIX sh bootstrap (ensures bash ≥ 4, execs install.bash)
├── install.bash                ← Real bash ≥ 4 installer
├── devcontainer-feature.json   ← Generated from metadata.yaml (used for ordering + lifecycle)
├── _lib/                       ← Full copy of the shared bash library (no network needed)
├── dependencies/               ← OS package manifest (when the feature has one)
└── files/                      ← Supplementary files (when the feature has any)
```

The bootstrap (`install.sh`) is identical across all features and handles bash ≥ 4 resolution the same way `get.sh` does. You can safely inspect every file in the tarball before running it.
:::

---

## Versioning and pinning

SysSet uses a two-level versioning scheme: **each feature is versioned independently** (the artifact you pin when you want to lock a single tool), and every CD run also publishes a **bundle release** (the snapshot you pin when you want a reproducible set of tools across your environment).

### Per-feature releases

Every feature is released under its own semver line, with a dedicated Git tag and GitHub release:

- **Git tag:** `<feature-id>/<X.Y.Z>` — e.g. `install-pixi/1.2.3`.
- **GitHub release:** per-tag, with a single asset `sysset-<feature-id>.tar.gz`.
- **OCI tags:** `ghcr.io/quantized8/sysset/<feature-id>:<major>`, `:<major>.<minor>`, `:<major>.<minor>.<patch>`.

Semver is applied per feature: a patch bump is behavior-preserving, a minor bump is backwards-compatible, a major bump is breaking.

### The bundle release (accumulator)

On every CD run that publishes at least one per-feature release, the pipeline also creates a **bundle release** under the tag `v<X.Y.Z>`. The bundle version is derived from the highest per-feature bump in that run (a new feature counts as `minor`, a removed one as `major`). Each bundle ships two assets:

| Asset                | Purpose                                                                                   |
|----------------------|-------------------------------------------------------------------------------------------|
| `sysset-all.tar.gz`  | Every feature's per-feature tarball, flat layout — convenient for mirrors and archives.    |
| `manifest.yaml`      | Machine-readable version map for this bundle, consumed by `get.bash` for bundle pinning.   |

:::{dropdown} Example `manifest.yaml`

```yaml
bundle: v1.2.0
commit: 3f7a…
features:
  install-fonts: 0.1.0
  install-pixi:  1.3.0
  install-shell: 0.2.0
```
:::

### Pinning — what you can choose

The installer exposes three orthogonal pinning mechanisms. You can combine them freely; conflicts are resolved by a well-defined priority order.

::::{grid} 1 1 3 3
:gutter: 2

:::{grid-item-card} Rolling
No pin. Every feature resolves to its latest per-feature release.<br/>Great for dev loops; never use for a release or archive.
:::

:::{grid-item-card} Per-feature (`@spec`)
Pin an individual feature to a version line. Uses the same spec grammar as an OCI tag.<br/>Great for hotfixes and bisects.
:::

:::{grid-item-card} Bundle (`SYSSET_VERSION`)
Pin **every** feature to the versions inside a specific bundle release.<br/>Great for reproducible multi-feature snapshots, archives, and air-gaps.
:::
::::

#### Per-feature spec grammar

Anywhere you pass a per-feature version — `@spec` on the CLI, a `:tag` on an OCI reference, or a value inside a manifest — these specs are accepted:

| Spec       | Resolves to              |
|------------|--------------------------|
| *(empty)*  | Latest across all majors |
| `latest`   | Same                     |
| `1`        | Latest `1.x.y`           |
| `1.2`      | Latest `1.2.x`           |
| `1.2.3`, `v1.2.3` | Exact          |

```sh
sh get.sh install-pixi@1            # latest 1.x.y
sh get.sh install-pixi@1.2          # latest 1.2.x
sh get.sh install-pixi@1.2.3        # exact 1.2.3
sh get.sh install-pixi@1.2 --version 0.66.0   # pin the tarball, pass --version through
```

The `@spec` suffix only affects *which* tarball is downloaded for that feature; all CLI flags after the feature ID (like `--version 0.66.0` above) are forwarded to the installer unchanged.

#### Bundle pinning

Set `SYSSET_VERSION` — or put a `v<major>.<minor>.<patch>` suffix on the `name` of a devcontainer manifest — to pin the **bundle** for the whole run. `get.bash` downloads the bundle's `manifest.yaml` first, then resolves each requested feature to the version listed there.

```sh
# Every feature pinned to the versions in bundle v1.2.0
SYSSET_VERSION=v1.2.0 sh get.sh install-pixi install-shell

# Partial specs and 'latest' also work (resolved against v* bundle tags)
SYSSET_VERSION=v1    sh get.sh my-setup.jsonc
SYSSET_VERSION=v1.2  sh get.sh my-setup.jsonc
SYSSET_VERSION=latest sh get.sh my-setup.jsonc
```

Inside a manifest, the equivalent pin is the optional version suffix on `name`:

```jsonc
{ "name": "my env v1.2.0",  "features": { /* … */ } }
```

#### Priority order

When more than one mechanism applies, the highest-priority wins:

```text
OCI per-feature tag (key:tag or @spec)
        ↓
SYSSET_VERSION  or  name's v<X.Y.Z> suffix  (bundle)
        ↓
Latest per-feature release  (rolling)
```

A per-feature override **always** wins over a bundle pin — useful for taking a point-fix on a single feature without giving up the pinned set for the rest:

```sh
# Pin everything to v1.2.0, except install-pixi which rolls to its latest 1.4.x
SYSSET_VERSION=v1.2.0 sh get.sh install-pixi@1.4 install-shell
```

---

## Manifest mode: `devcontainer.json` parity

`get.bash` reads a `devcontainer.json` (strict JSON) or `.jsonc` (with `//` and `/* */` comments and trailing commas — stripped before parsing) and honors a focused subset of the [official Dev Container spec](https://containers.dev/implementors/json_reference/), chosen so that the same file you use to build a container can also drive a host install.

### Honored fields

:::{list-table}
:header-rows: 1
:widths: 24 76

* - Field
  - Role
* - `name`
  - Optional. A trailing `v<major>.<minor>.<patch>` suffix can pin bundle resolution — equivalent to setting `SYSSET_VERSION`.
* - `features`
  - Object whose keys are OCI feature references (`ghcr.io/quantized8/sysset/<id>`, optionally with `:<tag>`) **or** local paths under the workspace that contain a `devcontainer-feature.json`. Values are the feature's options object (scalars only: booleans, strings, numbers).
* - `overrideFeatureInstallOrder`
  - Optional array of feature references. Earlier entries get **higher priority** within a scheduling round, after hard/soft dependency edges are satisfied.
* - `remoteUser` / `containerUser`
  - Used to set user-related env vars for installers and, when set, to run lifecycle command values as that user.
* - `initializeCommand`
  - Runs once on the **host** before any feature. Treated as untrusted (see warning below). CWD: `--initialize-command-dir` or the workspace folder.
* - `onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`, `postAttachCommand`
  - Container-level lifecycle. Merged with per-feature lifecycle values (from each feature's `devcontainer-feature.json`), in phase order. See [Lifecycle commands](#lifecycle-commands).
:::

:::{warning}
The contents of `initializeCommand` are executed on your host before any feature runs. Only point `get.sh` at manifests you trust (the installer prints `⚠️  initializeCommand (host): trust this config` as a reminder).
:::

### Ignored fields

Fields that only have meaning for a container build (buildah/docker image assembly, mount semantics, VS Code customizations, `portsAttributes`, `runArgs`, and similar) are skipped when `get.bash` reads the file. Unknown top-level keys are silently ignored, so the same manifest can drive both a dev container build and a host install without error.

### Rejected inputs

- **Duplicate keys** in JSON objects — hard error.
- **Non-scalar** feature option values (objects or arrays) inside `features[…]` — hard error. Use the [array type extension](#the-array-type-extension) (newline-delimited string) for list-valued options.
- Feature references outside the configured **compatible prefixes** — skipped with a warning (see `--compatible-prefix`).

### Full example

```jsonc
{
  // Bundle pin via the v*.*.* suffix on name; equivalent to SYSSET_VERSION=v1.2.0
  "name": "my env v1.2.0",
  "remoteUser": "dev",

  // Hard/soft dependency edges come from each feature's own metadata.
  // This list only breaks ties *within* a scheduling round.
  "overrideFeatureInstallOrder": [
    "ghcr.io/quantized8/sysset/setup-user",
    "ghcr.io/quantized8/sysset/install-shell"
  ],

  "features": {
    "ghcr.io/quantized8/sysset/setup-user":      { "username": "dev" },
    "ghcr.io/quantized8/sysset/install-shell:1": {
      "set_user_shells": "zsh",
      "ohmyzsh_theme":   "romkatv/powerlevel10k"
    },
    "ghcr.io/quantized8/sysset/install-pixi":    {}
  },

  "initializeCommand":      "echo 'prepping host'",
  "postCreateCommand":      "echo 'all done'"
}
```

---

## Install order

When `get.bash` installs multiple features, the order is determined by a **round-based topological sort** over a combined dependency graph:

1. **Hard edges** — from each feature's `dependsOn` in its generated `devcontainer-feature.json`. A feature cannot run until every hard dependency has completed.
2. **Soft edges** — from each feature's `installsAfter`. Honored whenever possible, but dropped if they would create a cycle.
3. **Priority** — `overrideFeatureInstallOrder` in the manifest. Earlier entries get higher priority *within the same round*; this is a tie-break, **not** an override of true dependency edges.
4. **Fallback** — if the graph is unsatisfiable for any reason, `get.bash` falls back to the canonical static order below, appending any remaining features at the end.

:::{dropdown} The canonical fallback order

```text
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
```

This order mirrors what the graph produces on a typical full-featured setup; the real install always prefers the graph-resolved order when one exists.
:::

The resolved order is printed to stderr at startup (`ℹ️  order: …`) so you can confirm what will run.

---

## Lifecycle commands

`get.bash` implements devcontainer-style lifecycle hooks, merged across the container-level manifest and the per-feature `devcontainer-feature.json` inside each tarball. Each phase's commands are run in order, and run as the resolved user (see below).

| Phase                  | Where it comes from                                                                  | Runs as                                 |
|------------------------|--------------------------------------------------------------------------------------|-----------------------------------------|
| `initializeCommand`    | Manifest only (no per-feature equivalent)                                            | Host user (before any feature)          |
| `onCreateCommand`      | Manifest + each feature's `devcontainer-feature.json`                                | `remoteUser` / `containerUser` (if set) |
| `updateContentCommand` | "                                                                                    | "                                       |
| `postCreateCommand`    | "                                                                                    | "                                       |
| `postStartCommand`     | "                                                                                    | "                                       |
| `postAttachCommand`    | "                                                                                    | "                                       |

Each command value follows the [devcontainer command form](https://containers.dev/implementors/json_reference/#lifecycle-scripts):

- **string** — run through a shell (`sh -c`).
- **array of strings** — run directly (no shell), `argv[0]` is the program.
- **object** — keys are command IDs, values are strings or arrays; all entries of the object are run **in parallel**.

Working directory:

- `initializeCommand` defaults to the manifest's workspace folder, overridable with `--initialize-command-dir`.
- All other phases default to the workspace folder, overridable with `--lifecycle-command-dir`.

### Disabling lifecycle commands

You can selectively skip lifecycle commands without editing the manifest. The grammar for `--no-feature-lifecycle-command` and `--no-container-lifecycle-command` is:

| Pattern                         | Disables                                                                 |
|---------------------------------|--------------------------------------------------------------------------|
| `all`                           | Every command in this scope (feature or container).                       |
| `<feature-id>`                  | Every command attached to the given feature (feature scope only).         |
| `<phase>`                       | Every command in the given phase, regardless of feature.                  |
| `<feature-id>:<phase>`          | Every command in that phase for that feature.                             |
| `<feature-id>:<phase>:<name>`   | One specific named command (when the value is an object form).            |

The flag is repeatable; each invocation adds a rule. Feature mode also accepts `--no-lifecycle` as a shortcut for "skip the installed feature's own hooks".

---

## `get.sh` and `get.bash` command-line reference

`get.sh` forwards every argument to `get.bash`, so the two have the same CLI. The wrapper-level flags below are consumed by `get.bash` itself; any extra arguments in feature mode are forwarded to the selected feature's `install.bash`.

```text
Usage:
  Feature mode:   get.sh <feature>[@<spec>] [feature-opts...]
  Manifest mode:  get.sh <devcontainer.json[.jsonc]>
```

::::{list-table}
:header-rows: 1
:widths: 36 64

* - Flag
  - Description
* - `--logfile <path>`
  - Append the full captured output to this file on exit (absolute path recommended). Secrets detected via `GITHUB_TOKEN` are redacted.
* - `--debug`
  - Enable `bash -x` trace inside `get.bash` itself. (To enable tracing inside a feature, pass `--debug` among its feature options or set the `DEBUG` env var.)
* - `--help`, `-h`
  - Print the embedded usage and exit.
* - `--workspace-folder <path>`
  - Default CWD for lifecycle commands (manifest mode); also the default CWD for the feature's own lifecycle hooks in feature mode. Defaults to the directory of the manifest (manifest mode) or `$PWD` (feature mode).
* - `--no-initialize-command`
  - Manifest mode only. Skip `initializeCommand` entirely.
* - `--initialize-command-dir <path>`
  - Manifest mode only. CWD used when running `initializeCommand`.
* - `--lifecycle-command-dir <path>`
  - CWD for every lifecycle command other than `initializeCommand`.
* - `--no-feature-lifecycle-command <pattern>`
  - Repeatable. Disable per-feature lifecycle commands using the [disable grammar](#disabling-lifecycle-commands).
* - `--no-container-lifecycle-command <pattern>`
  - Repeatable. Disable container-level (manifest) lifecycle commands using the same grammar.
* - `--compatible-prefix <oci-prefix>`
  - Repeatable. Sets of OCI prefixes accepted in `features[…]`. Defaults to `ghcr.io/quantized8/sysset/`. Unknown prefixes are skipped with a warning.
* - `--no-lifecycle`
  - Feature mode only. Skip the installed feature's lifecycle hooks (short-circuits the per-feature `devcontainer-feature.json` lifecycle).
::::

---

## Environment variables

Environment variables influence both `get.sh` (the POSIX bootstrap) and `get.bash` (the full installer). Set them on the process or export them in your shell before calling.

::::{list-table}
:header-rows: 1
:widths: 26 74

* - Variable
  - Description
* - `SYSSET_VERSION`
  - Bundle pin. Any spec understood by the version resolver (`""`, `latest`, `1`, `1.2`, `v1.2.3`, `1.2.3`). Per-feature `@spec` overrides still win. Equivalent to a `v*.*.*` suffix on the manifest's `name`.
* - `SYSSET_BASE_URL`
  - GitHub Releases base URL. Default: `https://github.com/quantized8/sysset/releases/download`. URLs are constructed as `<base>/<feature>/<X.Y.Z>/sysset-<feature>.tar.gz` for per-feature releases and `<base>/v<X.Y.Z>/manifest.yaml` for bundles. Override for mirrors (including `file://` paths).
* - `SYSSET_RAW_BASE`
  - Raw GitHub base for `get.bash` and `lib/*.sh`. Default: `https://raw.githubusercontent.com/quantized8/sysset/main`. Override to use a fork, a branch, or a local mirror.
* - `SYSSET_FETCH_TOOL`
  - Force `curl` or `wget`. Auto-detected when unset. Also exported by `get.sh` so `get.bash` inherits the same choice.
* - `LOGFILE`
  - Append the installer's captured output to this file on exit. Equivalent to `--logfile`. Also honored by individual features.
* - `GITHUB_TOKEN` *(optional)*
  - If set, used to authenticate GitHub API calls (avoids anonymous rate limits). Always masked in the captured log stream.
::::

---

## Release artifacts and naming conventions

Understanding the asset layout makes it easy to mirror releases, archive snapshots, or script custom installs.

### Per-feature release

| Item              | Value                                                                                        |
|-------------------|----------------------------------------------------------------------------------------------|
| Git tag           | `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`)                                            |
| GitHub Release    | One per tag                                                                                  |
| Single asset      | `sysset-<feature-id>.tar.gz`                                                                  |
| Download URL      | `https://github.com/quantized8/sysset/releases/download/<feature-id>/<X.Y.Z>/sysset-<feature-id>.tar.gz` |
| OCI image         | `ghcr.io/quantized8/sysset/<feature-id>`                                                     |
| OCI tags          | `:<major>`, `:<major>.<minor>`, `:<major>.<minor>.<patch>`                                   |

### Bundle release

| Item              | Value                                                                                        |
|-------------------|----------------------------------------------------------------------------------------------|
| Git tag           | `v<X.Y.Z>`                                                                                    |
| GitHub Release    | Marked as `latest` on the repository                                                          |
| Asset #1          | `sysset-all.tar.gz` — every per-feature tarball, flat layout                                  |
| Asset #2          | `manifest.yaml` — per-feature version map for the bundle                                      |
| Download URLs     | `https://github.com/quantized8/sysset/releases/download/v<X.Y.Z>/sysset-all.tar.gz`<br/>`https://github.com/quantized8/sysset/releases/download/v<X.Y.Z>/manifest.yaml` |

:::{dropdown} Publication strategy

CD is driven by pushes to `main`. On every CI-validated push, the pipeline looks at every `features/<id>/metadata.yaml`, queues features whose `version` has no matching `<id>/<version>` release yet, publishes their tarballs and GHCR images, then (if anything was published) computes the next bundle tag from the highest per-feature bump and publishes the bundle.

- A change to a shared library module (`lib/`) requires a version bump in every feature that embeds it; a CI guard refuses PRs that do not comply, so bundle snapshots never drift against published per-feature payloads.
- Re-runs are idempotent: already-published versions are skipped.
- A hotfix release for a single feature can be triggered manually via the CI workflow dispatch (`feature` + `version` inputs), without waiting for a new commit on `main`.

The full publishing pipeline is documented under {doc}`/dev-guide/publishing`.
:::

---

## Offline and air-gapped installs

The standalone channel is designed to work with no outbound network, provided you mirror two things: the tarballs from a bundle release, and (optionally) `get.bash` + `lib/` from the repo.

### Step 1 — stage the bundle

```sh
VERSION=v1.2.0

# Fetch both bundle assets once, somewhere you can copy them from later.
curl -fsSL "https://github.com/quantized8/sysset/releases/download/${VERSION}/sysset-all.tar.gz" \
  | tar xz -C /opt/sysset
curl -fsSL "https://github.com/quantized8/sysset/releases/download/${VERSION}/manifest.yaml" \
  -o /opt/sysset/manifest.yaml
```

At this point, each `sysset-<feature>.tar.gz` under `/opt/sysset` is a self-contained per-feature install, so you can already run any one of them offline:

```sh
tar xz -C /tmp/pixi < /opt/sysset/sysset-install-pixi.tar.gz
sudo sh /tmp/pixi/install.sh --version 0.66.0
```

### Step 2 — build a mirror matching the GitHub Releases URL layout

For `get.bash` manifest mode, build a mirror that mirrors `<base>/<feature>/<X.Y.Z>/sysset-<feature>.tar.gz` + `<base>/v<X.Y.Z>/manifest.yaml`. Then point `SYSSET_BASE_URL` at it:

```sh
VERSION=v1.2.0

mkdir -p /opt/sysset-mirror/${VERSION}
cp /opt/sysset/manifest.yaml /opt/sysset-mirror/${VERSION}/

python3 - <<'PY'
import pathlib, shutil, yaml
m = yaml.safe_load(pathlib.Path("/opt/sysset/manifest.yaml").read_text())
root = pathlib.Path("/opt/sysset-mirror")
src  = pathlib.Path("/opt/sysset")
for feat, ver in m["features"].items():
    dst = root / feat / ver
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / f"sysset-{feat}.tar.gz", dst / f"sysset-{feat}.tar.gz")
PY

SYSSET_BASE_URL="file:///opt/sysset-mirror" \
SYSSET_VERSION="${VERSION}" \
  sudo sh get.sh my-setup.jsonc
```

With `SYSSET_VERSION` set, `get.sh` downloads `manifest.yaml` from the mirror, then resolves each feature's version from it before downloading `<feature>/<X.Y.Z>/sysset-<feature>.tar.gz` — fully reproducible.

### Step 3 — fully air-gapped (`get.bash` + `lib/` offline too)

`get.sh` itself still downloads `get.bash` and `lib/*.sh` from `SYSSET_RAW_BASE`. For a completely offline host, mirror those too and override both bases:

```sh
SYSSET_RAW_BASE="http://my-mirror.internal/sysset" \
SYSSET_BASE_URL="file:///opt/sysset-mirror" \
SYSSET_VERSION="v1.2.0" \
  sudo sh get.sh my-setup.jsonc
```

Or skip `get.sh` entirely and run the per-feature tarballs directly — they contain everything needed to install, with zero outbound traffic.

---

## Logs, diagnostics, and recovery

Every feature goes through the same logging pipeline, which makes failures easy to triage.

- **Emoji markers** — stdout and stderr use a consistent vocabulary (`↪️` entry, `ℹ️` info, `📩` input read, `📦` install step, `⚠️` warning, `⛔` / `❌` error, `↩️` exit). Grep for `⛔` / `❌` in a log file to jump straight to failures.
- **`--logfile <path>`** (on `get.sh`, or `--logfile` as a feature option) captures the full `tee`d output. Append-safe; works across features in the same run.
- **`--debug`** enables `bash -x` inside the installer; combine with `--logfile` to capture the trace.
- **Partial failures** — in manifest mode, `get.bash` attempts every feature and exits non-zero if any failed, naming them at the end. Order is still respected: a feature whose hard dependencies failed is skipped.
- **Re-runs are idempotent** — installers check for already-done work and skip it, so you can rerun after fixing an environment issue without uninstalling first.

---

