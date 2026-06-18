## Usage

### As a Dev Container feature

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/devfeats/install-os-pkg:0": {
      "manifest": "/existing/path/packages.yaml"
      // or:   "/nonexistent/path/packages.json"
    }
  }
}
```

Inline manifests are also supported — the value is treated as inline content
when it contains a newline, and as a file path otherwise:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/devfeats/install-os-pkg:0": {
      "manifest": "packages: [git, curl, jq]\n"
      // or: "{\"packages\": [\"git\", \"curl\", \"jq\"]}\n"
    }
  }
}
```

>[!NOTE]
> One-line inline manifests must end with a newline character for proper detection.

### As a standalone installer script

The script can be piped directly from the network or run from a local copy.
Pass the manifest as a file path or an inline string via `--manifest`.
The script must run as root on Linux.
On macOS it may run as a regular user or with `sudo`.

```sh
# From a manifest file
curl -fsSL https://raw.githubusercontent.com/quantized8/devfeats/main/src/install-os-pkg/install.sh \
  | sudo bash -s -- --manifest /path/to/packages.yaml

# Inline manifest (trailing newline required for inline detection)
sudo bash install.sh --manifest $'packages:\n  - git\n  - curl\n  - jq\n'
```

After the feature has been installed (with `install_self` set to `true`),
a persistent wrapper is available at `/usr/local/bin/install-os-pkg`
and can be called directly by other features or lifecycle hook scripts (e.g., `postCreateCommand`):

```sh
install-os-pkg --manifest /workspace/.devcontainer/extra-packages.yaml
```

### As a dependency for another devcontainer feature

Other features can declare `install-os-pkg` as a dependency and call the
installer directly in their own `install.sh` to set up packages as part of
their own setup process:

```jsonc
// devcontainer-feature.json of another feature
{
  "dependsOn": {
    "ghcr.io/quantized8/devfeats/install-os-pkg:0": {
        "install_self": true
    }
  }
}
```

```sh
# install.sh of another feature
install-os-pkg --manifest $'packages:\n  - git\n  - curl\n'
```

---

## Manifest File Format

A manifest is a YAML (or JSON; both formats are accepted) document that declaratively describes what to
install and how. A formal JSON Schema is available at
[`/lib/ospkg-manifest.schema.json`](/lib/ospkg-manifest.schema.json) (published copy: `https://quantized8.github.io/devfeats/schema/ospkg-manifest.json`)
and can be referenced in editors for autocompletion and validation:

```yaml
# yaml-language-server: $schema=https://quantized8.github.io/devfeats/schema/ospkg-manifest.json
```

### Top-level structure

```yaml
# Packages to install
packages:
  - curl
  - git
  - jq

# Global scripts
prescripts: mkdir -p /opt/tools
scripts: echo "Done."

# PM-specific setup (only the active PM's block is evaluated)
apt:
  ppas: [ppa:deadsnakes/ppa]
brew:
  taps: [homebrew/cask-fonts]
```

All top-level keys are optional. A manifest with only `packages` is valid. A
manifest with only PM blocks (e.g. only `brew:` for cask installation) is
also valid. An empty manifest is valid but does nothing.

The full set of top-level keys:

| Key | Type | Description |
|---|---|---|
| `packages` | packageEntry[] | Packages to install. See [Package entries](#package-entries). |
| `prescripts` | script | Shell commands run before any PM operations. |
| `scripts` | script | Shell commands run after all packages are installed. |
| `apt` | object | APT-specific setup. See [PM blocks](#pm-blocks). |
| `apk` | object | APK-specific setup. |
| `brew` | object | Homebrew-specific setup. |
| `dnf` | object | DNF-specific setup. |
| `yum` | object | YUM-specific setup. |
| `pacman` | object | Pacman-specific setup. |
| `zypper` | object | Zypper-specific setup. |

### Package entries

The `packages` array accepts three entry types.

#### Bare strings

A bare string is a package name installed via the detected package manager:

```yaml
packages:
  - git
  - curl
  - jq
```

This is the simplest and most common form. A manifest containing nothing but
bare strings covers the vast majority of use cases.

#### Package objects

A package object provides PM-specific name overrides, version constraints,
conditions, flags, and inline setup. The required `name` field is the default
package name:

```yaml
packages:
  - name: ssl
    apt: libssl-dev
    apk: openssl-dev
    brew: openssl
    dnf: openssl-devel
    pacman: openssl
    zypper: libopenssl-devel
```

When the active PM has an explicit override key (e.g. `apt: libssl-dev`),
that override is used instead of `name`. If every target PM has an override,
`name` serves as a human-readable label — it is never passed to any PM.

Package object properties:

| Property | Type | Description |
|---|---|---|
| `name` | string | **Required.** Default package name or label. |
| `when` | condition | Condition filter. Package is skipped when the condition does not match. See [`when` clause](#when-clause). |
| `flags` | string \| string[] | Extra flags passed verbatim to the PM's install command (e.g. `--no-install-recommends`). |
| `version` | string | Plain version number (e.g. `1.2.3`). The installer builds the PM-native syntax automatically: `pkg=ver` on apt/apk/pacman/zypper, `pkg-ver` on dnf/yum, `pkg@ver` on brew. |
| `prescript` | script | Shell commands collected and run in the prescript phase. |
| `script` | script | Shell commands collected and run in the script phase. |
| `keys` | keyEntry[] | Signing keys collected and fetched in the key phase. See [Signing keys](#signing-keys). |
| `repos` | string[] | Repository definitions collected and added in the repo phase. |
| `apt`, `apk`, `brew`, `dnf`, `yum`, `pacman`, `zypper` | string | PM-specific package name override. |

#### Group objects

A group shares conditions, flags, and inline setup across multiple packages.
The required `packages` field distinguishes groups from package objects:

```yaml
packages:
  - label: Build tools
    when: { pm: apt }
    flags: --no-install-recommends
    packages:
      - build-essential
      - pkg-config
      - cmake
```

Groups can nest — a group's `packages` array can contain bare strings,
package objects, or further groups:

```yaml
packages:
  - label: Platform tools
    when: { kernel: linux }
    packages:
      - label: Debian family
        when: { id_like: debian }
        packages: [apt-transport-https, ca-certificates]
      - strace
```

A group's `when` condition ANDs with its children's `when` conditions. In the
example above, `apt-transport-https` requires both `kernel: linux` AND
`id_like: debian` to match. Nested groups stack: the effective condition is
the AND of all ancestor `when` clauses plus the entry's own.

A group's `flags` merge with per-package flags — group flags come first in
the argument list.

Group object properties:

| Property | Type | Description |
|---|---|---|
| `packages` | packageEntry[] | **Required.** The packages in this group. |
| `label` | string | Human-readable label shown in log output. |
| `when` | condition | Condition filter applied (AND'd) to all children. |
| `flags` | string \| string[] | Extra flags applied to all packages in the group. |
| `prescript` | script | Shell commands collected and run in the prescript phase. |
| `script` | script | Shell commands collected and run in the script phase. |
| `keys` | keyEntry[] | Signing keys collected and fetched in the key phase. |
| `repos` | string[] | Repository definitions collected and added in the repo phase. |

### `when` clause

The `when` clause is a condition filter that controls whether a package,
group, or PM block entry is evaluated. It supports two forms:

**Dictionary form** — keys within a dict are AND'd; array values within a
single key are OR'd:

```yaml
# pm must be apt AND arch must be x86_64
when: { pm: apt, arch: x86_64 }

# pm must be apt OR dnf (array values are OR'd within a key)
when: { pm: [apt, dnf] }
```

**List-of-dicts form** — each dict is a compound AND condition; the list is
OR'd:

```yaml
# (apt AND ubuntu) OR (dnf AND fedora)
when:
  - { pm: apt, id: ubuntu }
  - { pm: dnf, id: fedora }
```

#### Condition keys

The full set of keys from `/etc/os-release` is available, including any
distro-specific fields. Four additional synthetic keys are added:

| Key | Source | Example values |
|---|---|---|
| `pm` | Detected package manager (synthetic) | `apt`, `apk`, `brew`, `dnf`, `yum`, `pacman`, `zypper` |
| `arch` | `uname -m` (synthetic) | `x86_64`, `aarch64`, `armv7l`, `i686`, `arm64` |
| `kernel` | `uname -s` lowercased (synthetic) | `linux`, `darwin` |
| `deb_arch` | `dpkg --print-architecture` (APT only) | `amd64`, `arm64`, `armhf` |

> **Note:** `deb_arch` uses Debian's architecture naming convention (`amd64`
> instead of `x86_64`, `arm64` instead of `aarch64`). It is only populated
> when the active PM is `apt`. Use it in `[arch=…]` APT repository options
> and wherever a Debian-native arch string is expected. See
> [Variable substitution in repos and keys](#variable-substitution-in-repos-and-keys).

Common `/etc/os-release` keys available on every Linux distro:

| Key | `/etc/os-release` variable | Example values |
|---|---|---|
| `id` | `ID` (or `macos` on macOS) | `ubuntu`, `debian`, `alpine`, `fedora`, `arch`, `rhel` |
| `id_like` | `ID_LIKE` (or `macos`) | `debian`, `rhel`, `arch`, `suse` |
| `version_id` | `VERSION_ID` (or `sw_vers` on macOS) | `22.04`, `39`, `3.19`, `15.6` |
| `version_codename` | `VERSION_CODENAME` | `jammy`, `bookworm`, `noble` |
| `name` | `NAME` | `Ubuntu`, `Debian GNU/Linux`, `Alpine Linux` |
| `pretty_name` | `PRETTY_NAME` | `Ubuntu 22.04.3 LTS` |

Any other key present in `/etc/os-release` on the target system is also
available. A key absent from `/etc/os-release` evaluates as empty string.

All condition values are matched case-insensitively.

On macOS, where `/etc/os-release` does not exist, the condition keys are
populated synthetically — see [macOS support](#macos-support).

#### Evaluation rules

1. **Absent `when`** → the entry always matches.
2. **Single dict** → AND of all keys. Each key's value is a string or an
   array of strings (OR'd within the key). All keys must match.
3. **Array of dicts** → OR of compounds. Each element is evaluated as in (2).
   The entry matches if any element matches.
4. **Group stacking** → a group's `when` ANDs with each child's `when`.
   Nested groups stack: the effective condition is the AND of all ancestor
   conditions plus the entry's own.

### PM blocks

PM blocks are top-level keys named after a package manager. They contain
setup operations that are inherently PM-specific — signing keys, repositories,
taps, casks, modules, etc. Only the block matching the detected PM is
evaluated; all others are silently ignored.

```yaml
apt:
  ppas: [ppa:deadsnakes/ppa]
  keys:
    - url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      dest: /usr/share/keyrings/nodesource.gpg
  repos:
    - "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main"

brew:
  taps: [homebrew/cask-fonts]
  casks: [iterm2, visual-studio-code]

dnf:
  copr: [user/project]
  modules: ["nodejs:18/common"]
  groups: [development-tools]
```

#### Available keys per PM

| PM | Available keys |
|---|---|
| `apt` | `packages`, `ppas`, `keys`, `repos`, `scripts` |
| `apk` | `packages`, `repos`, `scripts` |
| `brew` | `packages`, `taps`, `casks`, `scripts` |
| `dnf` | `packages`, `copr`, `repos`, `modules`, `groups`, `keys`, `scripts` |
| `yum` | `packages`, `repos`, `groups`, `keys`, `scripts` |
| `pacman` | `packages`, `repos`, `keys`, `scripts` |
| `zypper` | `packages`, `repos`, `keys`, `scripts` |

#### `ppas` (APT only)

Ubuntu PPAs added via `add-apt-repository` before the package list refresh:

```yaml
apt:
  ppas: [ppa:deadsnakes/ppa, ppa:ubuntu-toolchain-r/test]
```

#### `taps` (Homebrew only)

Homebrew taps — third-party formula repositories cloned via `brew tap`.
Entries can be simple strings or objects with a custom URL:

```yaml
brew:
  taps:
    - homebrew/cask-fonts           # short name
    - name: user/repo              # object form with custom URL
      url: https://git.example.com/user/homebrew-repo.git
```

Taps are **not cleaned up** after installation — they persist in the Homebrew
prefix. The `keep_repos` option does not affect taps.

#### `casks` (Homebrew only)

macOS GUI applications installed via `brew install --cask`. No Linux
equivalent — cask entries are silently skipped on Linuxbrew.

```yaml
brew:
  casks: [iterm2, visual-studio-code, firefox]
```

#### `copr` (DNF only)

Fedora COPR repositories enabled via `dnf copr enable`:

```yaml
dnf:
  copr: [user/project]
```

#### `modules` (DNF only)

DNF module streams enabled via `dnf module enable`. Format:
`module:stream` or `module:stream/profile`:

```yaml
dnf:
  modules: ["nodejs:18/common", "php:8.2"]
```

#### `groups` (DNF/YUM only)

Package groups installed via `dnf groupinstall` or `yum groupinstall`:

```yaml
dnf:
  groups: [development-tools, "RPM Development Tools"]
```

#### `repos`

Repository definitions in the active PM's native format. Each entry is a
string written to the PM's drop-in configuration path (see
[Repository drop-in paths](#repository-drop-in-paths)).

Repo strings (and key `url` / `dest` values) support **variable
substitution** — see [Variable substitution in repos and
keys](#variable-substitution-in-repos-and-keys):

```yaml
apt:
  repos:
    - "deb [arch={deb_arch} signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main"
    - "deb [signed-by=/usr/share/keyrings/myppa.gpg] https://ppa.launchpadcontent.net/foo/ppa/ubuntu {version_codename} main"

dnf:
  repos:
    - |
      [docker-ce]
      name=Docker CE Stable
      baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/stable
      enabled=1
      gpgcheck=1
      gpgkey=https://download.docker.com/linux/fedora/gpg
```

#### `keys` (PM block)

Signing keys fetched before repositories are added. Same format as inline
keys (URL-based or fingerprint-based) — see [Signing keys](#signing-keys).

#### `scripts` (PM block)

Shell commands that run only when the corresponding PM is active. PM block
scripts run _after_ all packages and casks are installed, in the script phase
of the [pipeline](#pipeline-execution-order):

```yaml
apt:
  scripts: apt-get autoremove -y
brew:
  scripts: brew cleanup --prune=all
```

### Inline setup

Package objects and group objects can carry `keys`, `repos`, `script`, and
`prescript` inline, keeping all setup for a third-party package in one place:

```yaml
packages:
  - name: docker
    apt: docker-ce
    when: { pm: apt }
    keys:
      - url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.gpg
    repos:
      - "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable"
    script: systemctl enable docker
```

Inline keys, repos, and scripts are **collected** and executed in the
standard [pipeline order](#pipeline-execution-order) — not inline at the
point of definition. This structural co-location is for authoring
convenience; it does not change execution semantics. See
[Collected ordering](#collected-ordering) in the Developer Notes for merge
details.

### Signing keys

Keys are signing key entries fetched before any repository is added. `dest`
is always required. Exactly one of `url` or `fingerprint` must be provided:

```yaml
apt:
  keys:
    # URL-based: download the key from a URL.
    - url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      dest: /usr/share/keyrings/nodesource.gpg

    # Fingerprint-based: fetch from the Ubuntu keyserver (no URL needed).
    - fingerprint: "F911AB184317630C59970973E363C90F8F1B6217"
      dest: /usr/share/keyrings/git-core-ppa.gpg
```

Key entry properties:

| Property | Type | Description |
|---|---|---|
| `url` | string (URI) | URL to download the signing key from. Required unless `fingerprint` is provided. Supports [variable substitution](#variable-substitution-in-repos-and-keys). |
| `fingerprint` | string | 40-character hex GPG fingerprint. Fetched from the Ubuntu keyserver (HTTPS first, then HKP fallback). Required unless `url` is provided. |
| `dest` | string | **Required.** Destination file path for the key. Supports [variable substitution](#variable-substitution-in-repos-and-keys). |
| `dearmor` | boolean | Explicitly control dearmoring. When omitted, auto-detected from `dest` extension. |

Behaviour:

- If `dest` ends in `.gpg`, the key is automatically dearmored via
  `gpg --dearmor` (ASCII-armored PGP → binary keyring format required by
  modern APT `signed-by=` references). Set `dearmor: false` to override.
- `curl` (preferred) or `wget` is used for URL downloads. `gnupg` is used for
  dearmoring and keyserver lookups. Missing tools are **auto-installed** via
  the detected PM before proceeding.
- **Fingerprint fetch** tries HTTPS download from
  `keyserver.ubuntu.com` first; if that fails, falls back to HKP
  (`hkp://keyserver.ubuntu.com`, then `hkp://keyserver.pgp.com`).
- URL-based fetches are retried up to three times with a 3-second pause to
  handle transient network failures.
- GPG operations run in an isolated temporary `GNUPGHOME` directory that is
  removed after all keys are installed, so no trust-database artefacts
  pollute the container image layer.

Keys can appear in PM blocks or inline on package/group objects. All are
collected and processed together during the key phase of the
[pipeline](#pipeline-execution-order).

### Scripts

Scripts are shell commands run at two points in the pipeline:

- **`prescripts`** (top-level) / **`prescript`** (inline on packages/groups):
  Run before any PM operations (keys, repos, update, install).
- **`scripts`** (top-level, PM blocks) / **`script`** (inline on
  packages/groups): Run after all packages are installed, before repo cleanup
  and cache clean.

A script value can be a single string or an array of strings (joined with
newlines before execution):

```yaml
prescripts: mkdir -p /opt/tools

scripts:
  - ldconfig
  - echo "Installation complete"

packages:
  - name: docker
    apt: docker-ce
    script: systemctl enable docker

apt:
  scripts: apt-get autoremove -y
```

### Flags

The `flags` property passes extra arguments verbatim to the PM's install
command. It can be a string (split on whitespace) or an array of strings:

```yaml
packages:
  - name: vim
    flags: --no-install-recommends
    when: { pm: apt }

  - label: Minimal installs
    flags: [--no-install-recommends, --no-install-suggests]
    when: { pm: apt }
    packages: [git, curl]
```

Group flags are prepended to per-package flags when both are present.

---

## Supported package managers

Detection is automatic based on which binary is present. The first match
wins:

| Priority | Tool | Distro family |
|---|---|---|
| 1 | `apt-get` | Debian, Ubuntu |
| 2 | `apk` | Alpine |
| 3 | `dnf` | Fedora, RHEL 8+, CentOS Stream |
| 4 | `microdnf` | Minimal RHEL/UBI containers |
| 5 | `yum` | RHEL 7, CentOS 7, Amazon Linux |
| 6 | `zypper` | openSUSE, SLES |
| 7 | `pacman` | Arch Linux, Manjaro |
| 8 | `brew` | macOS, Linuxbrew |

On macOS (Darwin), `brew` is the **only** candidate — native package managers
do not exist. If `brew` is not found on macOS, the installer fails with an
actionable error message directing the user to install Homebrew first (via the
`install-homebrew` feature or the official Homebrew installer at
<https://brew.sh>).

On Linux, native package managers always take priority over `brew`. Homebrew
(Linuxbrew) is only used on Linux when no native PM is found. Set
`prefer_linuxbrew: true` to invert this — `brew` is then checked before the
native PM chain and will be selected if present, even alongside `apt-get` or
another native PM.

### macOS support

On macOS, Homebrew replaces the system package manager. The installer handles
macOS-specific concerns transparently:

**Condition keys** — Since `/etc/os-release` does not exist on macOS, the
`when` condition keys are populated synthetically:

| Key | Value | Source |
|---|---|---|
| `pm` | `brew` | Detection |
| `arch` | `arm64` or `x86_64` | `uname -m` |
| `kernel` | `darwin` | `uname -s` (lowercased) |
| `id` | `macos` | Synthetic |
| `id_like` | `macos` | Synthetic |
| `version_id` | e.g. `15.2` | `sw_vers -productVersion` |

This means `when: { pm: brew }` and `when: { id: macos }` are both valid
ways to target macOS in a manifest. Both work; the choice is a matter of
intent (`pm: brew` also matches Linuxbrew; `id: macos` targets macOS
specifically).

**Linuxbrew context** — When `prefer_linuxbrew: true` selects Homebrew on a
Linux host, `pm` is `brew` but the remaining keys (`id`, `id_like`,
`version_id`) still reflect the real Linux distro values from
`/etc/os-release`. This means:

- `when: { pm: brew }` matches both macOS brew and Linuxbrew.
- `when: { id: macos }` does **not** match Linuxbrew on Linux — use it when
  you need to target macOS exclusively.
- `when: { pm: brew, id: macos }` also targets macOS only.
- `when: { pm: brew, kernel: linux }` targets Linuxbrew on Linux only.

**Root privilege** — On Linux, the installer requires root for native PM
operations. On macOS, `brew` must run as a non-root user; the
`os__require_root` check is skipped when the detected PM is `brew`. The
`dry_run` option also skips the root check on all platforms.

**Brew user handling** — When the installer runs as root (as it always does
inside a devcontainer feature's `install.sh`), it handles brew's root
restriction transparently:

| Context | Action |
|---|---|
| Root in a container (Docker, Podman, K8s, CI) | Run brew directly — [brew allows root in containers](#brew-root-handling) |
| Root on bare metal | `su` to the owner of `$(brew --prefix)` |
| Non-root | Run brew directly |

No user-facing `brew_user` option is needed. See the
[Developer Notes](#brew-user-handling) for the full rationale and brew's
source code.

---

## Pipeline execution order

When processing a manifest, the installer executes phases in this fixed
order:

1. **Prescripts** — top-level `prescripts` + collected from packages/groups.
2. **Keys** — PM block `keys` + collected from packages/groups.
3. **Repos** — PM block `repos` + collected from packages/groups.
4. **PM-specific setup** — PPAs (apt), taps (brew), COPR (dnf).
5. **Update** — `apt-get update` / `brew update` / `apk update` / etc.
   Skipped when `update` is `false`, or when lists are fresh per
   `lists_max_age`, unless a new repo was just added.
6. **Modules** — `dnf module enable` (DNF only).
7. **Groups** — `dnf groupinstall` / `yum groupinstall` (DNF/YUM only).
8. **Packages** — `packages` array, resolved per active PM.
9. **Casks** — `brew install --cask` (Homebrew only).
10. **Scripts** — PM block `scripts` + top-level `scripts` + collected from
    packages/groups.
11. **Repo cleanup** — remove drop-in repo files (unless `keep_repos`).
12. **Cache clean** — `apt-get clean` / `brew cleanup` / etc. (unless
    `keep_cache`).

Inline keys, repos, and scripts from packages and groups are merged with
their corresponding PM block and top-level entries before execution. Within
each phase, collected items are processed in manifest declaration order. See
[Collected ordering](#collected-ordering) in the Developer Notes for details.

---

## Variable substitution in repos and keys

Repo strings (`repos[]` entries) and key `url` and `dest` values support
`{key}` substitution at runtime. The available substitution keys are the
same as the [condition keys](#condition-keys) — i.e. all `/etc/os-release`
fields plus the synthetic keys (`pm`, `arch`, `kernel`, `deb_arch`):

```yaml
apt:
  keys:
    - url: "https://cli.github.com/packages/githubcli-archive-keyring.gpg"
      dest: /etc/apt/keyrings/githubcli-archive-keyring.gpg
      dearmor: false
  repos:
    - "deb [arch={deb_arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"

packages:
  - name: git
    when: { id: ubuntu, pm: apt }
    keys:
      - fingerprint: "F911AB184317630C59970973E363C90F8F1B6217"
        dest: /usr/share/keyrings/git-core-ppa.gpg
    repos:
      - "deb [signed-by=/usr/share/keyrings/git-core-ppa.gpg] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu {version_codename} main"
```

Substitution behaviour:

- `{key}` tokens are replaced with the runtime value of the corresponding
  OS-release / synthetic context key.
- Unknown tokens (no matching key in the context) are **left unchanged**.
- Substitution happens at the point of key fetch / repo write, _after_ the
  manifest is parsed — it is a runtime expansion, not a YAML preprocessor.
- `{deb_arch}` is particularly useful for APT `[arch=…]` options to avoid
  hardcoding `amd64` or `arm64` in manifests that must run on multiple
  architectures.

---

## Dry run

Set `dry_run: true` in `devcontainer.json`, pass `--dry_run` on the CLI, or
set `DRY_RUN=true` as an environment variable to print what the installer
would do without making any changes. No packages are installed, no files are
written, and no scripts are executed. Root privilege is not required.

```sh
install-os-pkg --manifest /path/to/packages.yaml --dry_run
```

Example output:

```
🔍 Dry-run mode enabled — no changes will be made.
🔍 [dry-run] key: 1 entry/entries — would fetch:
    https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key → /usr/share/keyrings/nodesource.gpg
🔍 [dry-run] repo: 1 line(s) — would add to package manager repos.
🔍 [dry-run] update: would run: apt-get update
🔍 [dry-run] packages (2): nodejs curl
🔍 [dry-run] cache clean: would run clean_apt
```

> **Note:** When used as a devcontainer feature, the build step succeeds
> without installing anything, which is useful for manifest auditing or
> troubleshooting selector logic in CI.

---

## Lifecycle hook

By default the feature installs packages at **image build time** (inside the
`docker build` step). Setting `lifecycle_hook` defers installation to a
devcontainer lifecycle event that runs _after_ the container is created, with
the workspace fully mounted.

```jsonc
{
  "features": {
    "ghcr.io/quantized8/devfeats/install-os-pkg:0": {
      "manifest": "/workspace/.devcontainer/packages.yaml",
      "lifecycle_hook": "postCreate"
    }
  }
}
```

Supported values:

| Value | When it runs |
|---|---|
| `onCreate` | Once, after the container is created and the workspace is mounted. |
| `updateContent` | Once when the workspace content changes (e.g. a new clone). |
| `postCreate` | Once, after `onCreate` and `updateContent` have completed. |

When `lifecycle_hook` is set:

- The feature writes a hook script to
  `/usr/local/share/install-os-pkg/<hook-name>.sh` (e.g. `post-create.sh`).
- No packages are installed during the build step.
- If the manifest value is inline content it is saved to
  `/usr/local/share/install-os-pkg/manifest.yaml` so it is accessible at
  hook runtime.
- All other options (`log_level`, `keep_repos`, `log_file`, etc.) are forwarded
  into the hook script automatically.
- The other two lifecycle commands are registered as safe no-ops (the files
  for those hooks are absent, so the conditional test in the lifecycle
  command is a no-op).

> **Note:** `lifecycle_hook` requires a non-empty `manifest`.

---

## System paths

| Path | Purpose |
|---|---|
| `/usr/local/bin/install-os-pkg` | Wrapper script (written when `install_self=true`). |
| `/usr/local/lib/install-os-pkg/install.sh` | Library copy of the main installer. |
| `/usr/local/share/install-os-pkg/` | Hook scripts and saved manifests (only when `lifecycle_hook` is set). |

---

## Repository drop-in paths

When a manifest adds repositories (via `repos` in PM blocks or inline on
packages/groups), the installer writes content to a PM-specific drop-in
location before the update and install steps. Unless `keep_repos` is `true`,
the files are deleted after installation so they do not persist in the image.

| Package manager | Drop-in location |
|---|---|
| APT | `/etc/apt/sources.list.d/syspkg-installer.list` |
| APK | Lines appended to `/etc/apk/repositories` (reversed on cleanup) |
| DNF / YUM | `/etc/yum.repos.d/syspkg-installer.repo` |
| Zypper | `/etc/zypp/repos.d/syspkg-installer.repo` |
| Pacman | `/etc/pacman.d/syspkg-installer.conf` + `Include` line in `/etc/pacman.conf` |
| Homebrew | N/A — taps are Git clones into the Homebrew prefix, not drop-in files. They are always kept. |

---

## Full examples

### Minimal manifest

A manifest with only package names and no extra configuration:

```yaml
packages:
  - git
  - curl
  - jq
  - ripgrep
```

### Cross-platform development tools

```yaml
packages:
  - git
  - curl
  - jq

  - name: ssl
    apt: libssl-dev
    apk: openssl-dev
    brew: openssl
    dnf: openssl-devel
    yum: openssl-devel
    pacman: openssl
    zypper: libopenssl-devel

  - label: Build essentials (Debian)
    when: { pm: apt }
    flags: --no-install-recommends
    packages: [build-essential, pkg-config, cmake]

  - label: Build essentials (Alpine)
    when: { pm: apk }
    packages: [build-base, pkgconf, cmake]

  - label: Build essentials (Fedora)
    when: { pm: dnf }
    packages: [gcc, gcc-c++, make, pkgconf-pkg-config, cmake]
```

### Third-party APT repository (Node.js)

```yaml
apt:
  keys:
    - url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      dest: /usr/share/keyrings/nodesource.gpg
  repos:
    - "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main"

packages:
  - name: nodejs
    when: { pm: apt }
```

### Docker CE with inline setup

All signing key, repository, and post-install configuration co-located with
the package entry. `{deb_arch}` and `{version_codename}` are substituted
at runtime — no hardcoded `amd64` or `jammy`:

```yaml
packages:
  - name: docker
    apt: docker-ce
    when: { pm: apt }
    keys:
      - url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.gpg
    repos:
      - "deb [arch={deb_arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu {version_codename} stable"
    script: systemctl enable docker
```

### Homebrew with taps and casks

```yaml
brew:
  taps:
    - homebrew/cask-fonts
    - name: user/tools
      url: https://git.example.com/user/homebrew-tools.git
  casks:
    - iterm2
    - visual-studio-code
    - firefox

packages:
  - name: terminal-tools
    brew: bat
  - name: search
    brew: ripgrep
  - name: shell
    brew: fish
```

### Architecture-conditional packages

```yaml
packages:
  - label: Performance tools
    when: { kernel: linux, arch: x86_64 }
    packages: [linux-perf, valgrind]

  - label: Cross-compile tools
    when:
      - { pm: apt, arch: aarch64 }
      - { pm: dnf, arch: aarch64 }
    packages: [gcc-x86-64-linux-gnu]
```

### Mixed Linux and macOS

```yaml
packages:
  - git
  - curl
  - name: ssl
    apt: libssl-dev
    brew: openssl

  - label: macOS development
    when: { id: macos }
    packages:
      - name: compiler
        brew: llvm

brew:
  casks: [iterm2, rectangle]

apt:
  ppas: [ppa:deadsnakes/ppa]

scripts: echo "Setup complete on $(uname -s)"
```

---

## Troubleshooting

### No supported package manager found (macOS)

If the installer fails with "No supported package manager found" on macOS,
Homebrew needs to be installed first. Use the `install-homebrew` feature
(which is automatically ordered before `install-os-pkg` when both are
present via `installsAfter`) or install Homebrew manually from
<https://brew.sh>.

### YAML parse error

Ensure the manifest is valid YAML. Common issues:

- Unquoted strings containing special characters (`:`, `@`, `#`, `[`, `]`).
  Repository lines almost always need quoting:
  `"deb [signed-by=...] https://..."`.
- Indentation errors — YAML uses spaces, not tabs.
- Missing quotes around version constraints containing `=` or `>`.

Add the JSON Schema reference to the top of your manifest file to enable IDE
validation and autocompletion:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/QuanTizEd8/DevFeats/main/src/install-os-pkg/manifest.schema.json
```

### Packages not found after adding a repository

Check that `update` is not set to `false`. When a manifest adds
repositories, the package list update must run before installation. The
installer automatically forces an update when a new repo is added, unless
`update: false` overrides this behaviour.

### Brew refuses to run as root

This should not occur inside containers — brew explicitly allows root in
Docker, Podman, Kubernetes, and CI environments. If it does occur, the
container environment may not be detectable (missing `/.dockerenv` or
`/run/.containerenv`, no matching cgroup entries). As a workaround, ensure
the Homebrew prefix exists and is owned by a non-root user, or run the
installer as that user directly.

---

## References

- [devcontainer features specification](https://containers.dev/implementors/features/)
- [devcontainer lifecycle hooks](https://containers.dev/implementors/spec/#lifecycle)
- [APT documentation](https://manpages.debian.org/stable/apt/apt-get.8.en.html)
- [APK wiki](https://wiki.alpinelinux.org/wiki/Alpine_Package_Keeper)
- [Homebrew documentation](https://docs.brew.sh/)
- [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux)
- [Homebrew FAQ — running as root](https://docs.brew.sh/FAQ)
- [DNF documentation](https://dnf.readthedocs.io/)
- [YUM man page](https://man7.org/linux/man-pages/man8/yum.8.html)
- [Pacman wiki](https://wiki.archlinux.org/title/Pacman)
- [Zypper manual](https://en.opensuse.org/SDB:Zypper_manual)
- [os-release specification (FreeDesktop)](https://www.freedesktop.org/software/systemd/man/latest/os-release.html)
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/json-schema-core)
- [`manifest.schema.json`](../../src/install-os-pkg/manifest.schema.json) — formal JSON Schema for YAML/JSON manifests









# ospkg Manifest Format

Manifests are consumed by `ospkg__run --manifest <file-or-inline>`.
Manifests are written in **YAML** (or **JSON**) format.

---

## YAML / JSON Manifest

### Top-level structure

```yaml
# Optional global condition — skips the entire manifest if false.
when: {pm: apt}

# Signing keys fetched before repos/packages.
keys:
  - url: https://example.com/key.gpg
    dest: /usr/share/keyrings/example.gpg   # ends in .gpg → auto-dearmored
  - url: https://example.com/key.asc
    dest: /etc/apt/trusted.gpg.d/example.gpg
    dearmor: true                           # explicit
  - fingerprint: "AABBCCDDEEFF00112233445566778899AABBCCDD"  # fetch from Ubuntu keyserver
    dest: /usr/share/keyrings/example.gpg

# Repository lines to add (PM-native format).
# {key} tokens are substituted at runtime from the OS-release / synthetic context
# (e.g. {deb_arch} → amd64/arm64, {version_codename} → jammy/bookworm).
repos:
  - content: "deb [arch={deb_arch} signed-by=...] https://repo.example.com stable main"

# APT PPAs (apt-add-repository).
ppas:
  - "ppa:git-core/ppa"

# Homebrew taps (brew only).
taps:
  - homebrew/core
  - name: my-org/tap
    url: https://github.com/my-org/homebrew-tap

# DNF COPR repos.
copr:
  - "user/reponame"

# DNF module streams.
modules:
  - "nodejs:18"

# Package groups (dnf group install / zypper pattern / pacman group).
groups:
  - "@development-tools"

# Shell commands run before package installation.
prescripts: |
  install -d /opt/myapp

# Unconditional packages (all PMs).
packages:
  - git
  - name: curl
    when: {pm: apt}
  - name: htop
    version: "3.2.1"          # becomes htop=3.2.1 on apt/apk/pacman/zypper, htop-3.2.1 on dnf/yum, htop@3.2.1 on brew
  - name: some-pkg
    flags: "--allow-unauthenticated"   # appended to the install command

# Per-PM package lists (override or supplement `packages`).
apt:
  packages:
    - build-essential
    - libssl-dev
brew:
  packages:
    - gnu-sed
  casks:
    - visual-studio-code

# macOS Homebrew casks (top-level shorthand).
casks:
  - iterm2

# Shell commands run after package installation.
scripts: |
  ldconfig
```

### Per-PM blocks

Any of the following top-level keys are evaluated only when the active PM matches:
`apt`, `brew`, `dnf`, `apk`, `yum`, `zypper`, `pacman`.

Each accepts a `packages` list. `brew` also accepts `casks` and `taps`.

```yaml
apt:
  packages:
    - libssl-dev
brew:
  taps:
    - homebrew/cask-fonts
  packages:
    - gnu-sed
  casks:
    - font-hack-nerd-font
```

### `when` clause

A `when` expression is supported at:
- Manifest top level (skips entire manifest if false)
- Individual package objects
- Group objects

`when` accepts a **mapping** (AND of all keys) or a **list of mappings** (OR of ANDs):
```yaml
when: { pm: apt }                   # pm == apt
when: { pm: [apt, apk] }            # pm == apt OR pm == apk
when: [{ pm: apt }, { pm: apk }]    # same — OR across objects
when: { pm: apt, id: debian }       # pm == apt AND id == debian
```

`when` values are matched case-insensitively. A key absent from the context evaluates as empty string.

Available condition keys — all `/etc/os-release` fields plus four synthetics:

| Field | Source |
|-------|--------|
| `pm` | Detected package manager: `apt`, `brew`, `dnf`, `apk`, `yum`, `zypper`, `pacman` |
| `kernel` | `linux` or `darwin` (synthetic) |
| `arch` | CPU architecture: `x86_64`, `aarch64`, `arm64`, etc. (synthetic) |
| `deb_arch` | Debian arch string: `amd64`, `arm64`, `armhf` — APT only (synthetic) |
| `id` | `/etc/os-release` `ID` (or `macos` on macOS) |
| `id_like` | `/etc/os-release` `ID_LIKE` |
| `version_id` | `/etc/os-release` `VERSION_ID` |
| `version_codename` | `/etc/os-release` `VERSION_CODENAME` (e.g. `jammy`, `bookworm`) |
| _(any other key)_ | Any other field present in `/etc/os-release` on the target system |

### Package objects

Packages may be plain strings or objects:

```yaml
packages:
  - git                          # plain string
  - name: curl                   # object — supports all fields below
    when: { pm: [apt, brew] }
    version: "8.0.1"
    flags: "--no-install-recommends"
```

| Field | Description |
|-------|-------------|
| `name` | Package name (required) |
| `when` | Condition (same syntax as top-level `when`) |
| `version` | Plain version number (e.g. `1.2.3`). The installer builds PM-native syntax automatically (`pkg=ver` apt/apk/pacman/zypper, `pkg-ver` dnf/yum, `pkg@ver` brew). |
| `flags` | Extra flags appended to the install command |

## Further Reading

- [`features/install-os-pkg/NOTES.md`](../../features/install-os-pkg/NOTES.md) — user-facing `install-os-pkg` documentation; [`features/install-os-pkg/manifest.schema.json`](../../features/install-os-pkg/manifest.schema.json) — manifest schema
