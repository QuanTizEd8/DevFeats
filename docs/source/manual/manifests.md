# Manifest Mode

When `install.sh`'s first argument ends in `.json` or `.jsonc`, it switches to **manifest mode**: it reads a `devcontainer.json` (or `.jsonc`) file and installs every entry under `features` on the host machine — no container toolchain required. The same file that drives a container build can drive a host install.

```sh
sudo sh install.sh .devcontainer/devcontainer.jsonc
```

---

## Honored fields

`install.bash` reads a focused subset of the [Dev Containers spec](https://containers.dev/implementors/json_reference/), chosen so the same manifest works for both a container build and a host install.

:::{list-table}
:header-rows: 1
:widths: 24 76

* - Field
  - Role
* - `name`
  - Optional. Human label only. A trailing `v<major>.<minor>.<patch>` suffix is ignored by installer resolution.
* - `features`
  - Object whose keys are OCI feature references (`ghcr.io/|{{github_user}}|/|{{github_repo}}|/<id>`, optionally with `:<tag>`) **or** local paths containing a `devcontainer-feature.json`. Values are the feature's options object (scalars: booleans, strings, numbers).
* - `overrideFeatureInstallOrder`
  - Optional array of feature references. Earlier entries get **higher priority** within a scheduling round, after hard/soft dependency edges are satisfied.
* - `remoteUser` / `containerUser`
  - Sets user-related environment variables for installers and is used to run lifecycle command values as that user.
* - `initializeCommand`
  - Runs once on the **host** before any feature. Treated as untrusted — see warning below.
* - `onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`, `postAttachCommand`
  - Container-level lifecycle. Merged with per-feature lifecycle values from each feature's `devcontainer-feature.json`, in phase order.
:::

:::{warning}
The contents of `initializeCommand` are executed on your host before any feature runs. Only point `install.sh` at manifests you trust (the installer prints a reminder when it encounters one).
:::

## Ignored fields

Fields that only have meaning for a container build (image assembly, mount semantics, VS Code customizations, `portsAttributes`, `runArgs`, and similar) are silently skipped. Unknown top-level keys are also ignored, so the same manifest can drive both a container build and a host install without error.

## Rejected inputs

- **Duplicate keys** in JSON objects — hard error.
- **Non-scalar** feature option values (objects or arrays) inside `features[…]` — hard error. Use the [array type](options.md#the-array-type) (newline-delimited string) for list-valued options.
- Feature keys that are neither valid OCI references nor local feature paths — skipped with a warning.

## Full example

```jsonc
{
  // Name is metadata only; version resolution comes from each feature key/spec.
  "name": "my env v1.2.0",
  "remoteUser": "dev",

  // Tie-breaking order within a scheduling round (does not override dependency edges)
  "overrideFeatureInstallOrder": [
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user",
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell"
  ],

  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user":      { "username": "dev" },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell:1": {
      "set_user_shells": "zsh",
      "ohmyzsh_theme":   "romkatv/powerlevel10k"
    },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi":    {}
  },

  "initializeCommand": "echo 'prepping host'",
  "postCreateCommand": "echo 'all done'"
}
```

---

## Install order

When installing multiple features, `install.bash` determines order via a **round-based topological sort** over a combined dependency graph:

1. **Hard edges** — from each feature's `dependsOn` in its `devcontainer-feature.json`. A feature cannot run until every hard dependency has completed.
2. **Soft edges** — from each feature's `installsAfter`. Honored where possible; dropped if they create a cycle.
3. **Alias resolution** — dependency references are matched against both feature IDs and `legacyIds`, so renamed features still satisfy `dependsOn`, `installsAfter`, and `overrideFeatureInstallOrder`.
4. **Priority** — `overrideFeatureInstallOrder` in the manifest. Earlier entries get higher priority *within the same round* — this is a tie-break, not an override of dependency edges.
5. **Fallback** — if the graph is unsatisfiable, `install.bash` falls back to a canonical static order, appending remaining features at the end.

:::{dropdown} Canonical fallback order

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

This mirrors what the dependency graph produces for a typical full-featured setup. The real install always prefers the graph-resolved order when one exists.
:::

The resolved order is printed to stderr at startup (`ℹ️  order: …`) so you can confirm what will run.

## Lockfiles

Use `--lockfile <path>` with manifest installs to persist the resolved OCI refs used for each feature key. Use `--frozen-lockfile <path>` to require those exact refs on future runs (fails if an entry is missing).

This is useful for deterministic CI and protects against mutable-tag drift between runs.

## OCI key compatibility

Manifest feature keys are treated as OCI references when they include a registry host and a path. A tag or digest is optional (`:latest` is implied when absent). Supported registry host forms include:

- FQDN hosts (for example `ghcr.io`, `registry.example.com`)
- `localhost` and `localhost:<port>`
- bracketed IPv6 hosts (for example `[2001:db8::1]:5000`)

---

## Lifecycle commands

`install.bash` implements devcontainer-style lifecycle hooks, merged across the container-level manifest and per-feature `devcontainer-feature.json` files inside each tarball. Each phase's commands run in order as the resolved user.

| Phase | Source | Runs as |
|-------|--------|---------|
| `initializeCommand` | Manifest only | Host user (before any feature) |
| `onCreateCommand` | Manifest + each feature | `remoteUser` / `containerUser` if set |
| `updateContentCommand` | " | " |
| `postCreateCommand` | " | " |
| `postStartCommand` | " | " |
| `postAttachCommand` | " | " |

Each command value follows the [devcontainer command form](https://containers.dev/implementors/json_reference/#lifecycle-scripts):

- **string** — run through a shell (`sh -c`).
- **array of strings** — run directly (no shell), `argv[0]` is the program.
- **object** — keys are command IDs, values are strings or arrays; all entries of the object run **in parallel**.

Working directory:

- `initializeCommand` defaults to the manifest's workspace folder, overridable with `--initialize-command-dir`.
- All other phases default to the workspace folder, overridable with `--lifecycle-command-dir`.

### Disabling lifecycle commands

Use `--no-feature-lifecycle-command` and `--no-container-lifecycle-command` to selectively skip commands without editing the manifest. Both flags are repeatable; each invocation adds a rule.

| Pattern | Disables |
|---------|----------|
| `all` | Every command in this scope (feature or container) |
| `<feature-id>` | Every command attached to the given feature (feature scope only) |
| `<phase>` | Every command in the given phase, regardless of feature |
| `<feature-id>:<phase>` | Every command in that phase for that feature |
| `<feature-id>:<phase>:<name>` | One specific named command (object form only) |

In feature mode, `--no-lifecycle` is a shortcut that skips the installed feature's own hooks entirely.
