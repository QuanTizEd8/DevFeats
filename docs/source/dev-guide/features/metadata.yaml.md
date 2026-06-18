# `metadata.yaml`

`features/<feature-id>/metadata.yaml` is the primary source of truth for a feature. It drives:

1. `src/*/devcontainer-feature.json` — the OCI-compliant feature spec consumed by the devcontainer CLI
2. `src/*/install.bash` header — argument parsing, env var injection, library sourcing, option validation
3. `src/*/dependencies/*.yaml` — OS package manifests installed before `install.bash` runs
4. Documentation — options table and examples on the feature's reference page

Validated against `features/metadata.schema.json` at every `just sync-src`.

## Required Top-Level Fields

```yaml
version: 1.2.3        # feature semver; must be bumped on any behaviour change (CI enforces this)
name: My Tool         # human-readable display name shown in tool UIs
description: ...      # one-line description
keywords: [tool, dev] # searchable tags
```

The top-level `version` is the **feature release version** (what gets tagged on GHCR/GitHub Releases). It is separate from the shared **`version` install option** (tool version to install), which is injected from `metadata.shared.yaml` when `_options.version` is declared.

`id`, `documentationURL`, and `licenseURL` are derived at sync time — do not add them to `metadata.yaml`.

## Options

Each option declared in `options:` becomes a CLI flag (`--<option_name>`) and an env var (`<OPTION_NAME>`) injected at install time.

```yaml
options:
  version:
    type: string
    default: stable
    description: Version to install.
    proposals:
      - value: latest
        description: Latest release including pre-releases.
      - value: stable
        description: Latest final release.

  method:
    type: string
    default: auto
    description: Installation method.
    enum:
      - value: auto
        description: Determine best method at runtime.
      - value: binary
        description: Install pre-built binary from GitHub.
      - value: package
        description: Install via OS package manager.
```

**Option types:**

| Type | Behaviour |
|------|-----------|
| `string` | Plain string; use `enum` (strict) or `proposals` (suggestive) for UI hints |
| `boolean` | True/false checkbox in supporting UIs |
| `array` | DevFeats extension: newline-delimited list; serialized as `type: string` in generated JSON |

**`enum` vs `proposals`:**

| Key | Behaviour |
|-----|-----------|
| `enum` | Strict — only listed values accepted; UI shows a dropdown |
| `proposals` | Suggestive — listed values appear as suggestions; any other value is also valid |

### Internal Option Keys

| Key | Where used | Purpose |
|-----|-----------|---------|
| `_applies_when` | Per-feature `metadata.yaml` | **Runtime** condition list. Option is active/shown only when matching conditions hold. Array of objects: within each object all key-value pairs are AND-ed; multiple objects are OR-ed. Example: `[{method: [source]}]` — active only when `method` is `source`. |
| `_apply_when` | `metadata.shared.yaml` only | **Sync-time** boolean. A `#{{ python }}#` expression; if falsy, the shared option is excluded from that feature entirely. |
| `_path` | Either | File-test validation (e.g. `-f`, `-d`, `-x`) generated into the install-script header; skipped when the option is empty |
| `_uri` | Either | Marks an option as URI-capable. `true` fetches the URI to a temp file; object form: `{chmod: "+x"}` for executables or `{chmod: "600"}` for credential files |

For `type: array` options, generated scripts trim each element and drop empty entries before URI resolution and validation.

## Shared Options

`features/metadata.shared.yaml` defines options auto-injected into every feature at sync time. **Do not redeclare any of these in per-feature `metadata.yaml`:**

- `version` — version to install (proposals: `latest`, `stable`, semver)
- `method` — installation method (`auto` | `binary` | `package` | ...)
- `log_level` — verbosity (`silent | error | warn | info | debug | trace`)
- `log_file` — path to capture install log
- `log_file_level` — file log verbosity (default: `trace`, enables bash xtrace)
- `if_exists` — behavior when tool is already present (`skip | fail | reinstall | update | uninstall`)
- Additional options for common patterns (`keep_cache`, `keep_build_deps`, fetch headers, etc.)

The exact set is defined in `features/metadata.shared.yaml` and filtered per-feature by `_apply_when` expressions that check which `_options` keys the feature declares.

---

## `_options` — The Declarative Framework

The `_options` object is the most important key in `metadata.yaml`. It tells the framework **what to auto-implement** in `install.bash`. Instead of writing boilerplate code, you declare what your feature needs and the template generates the machinery.

```yaml
_options:
  gh_repo: owner/repo
  version:
    resolution: github_release
    default: stable
    inputs: [stable, latest, semver]
  method:
    binary:
      asset_uri: "https://github.com/{GH_REPO}/releases/download/{TAG}/tool-{VERSION}-{OS}-{ARCH}.tar.gz"
      binary_src: tool
    package: {}
  prefix:
    bins: [tool]
  completions:
    subcmd: completion --shell
```

With the above declaration alone, the framework auto-implements:
- Version resolution against GitHub Releases API
- Binary download, checksum verification, extraction, and installation at `PREFIX/bin/tool`
- OS package manager installation
- `__resolve_method` (selects `binary` on most platforms, `package` where configured)
- Shell completion generation for bash, zsh, fish
- PATH export or symlinking

### `_options.gh_repo`

GitHub repository slug. Used to generate `VERSION_URI` automatically.

```yaml
_options:
  gh_repo: cli/cli          # single repo: "owner/repo"
```

Multiple repos (when a feature manages several tools):
```yaml
_options:
  gh_repo:
    gh:
      tool_name: GitHub CLI
      slug: cli/cli
    ghec:
      tool_name: GHEC CLI
      slug: github/ghec-importer
```

### `_options.version`

Declares how to resolve user-provided version specs to concrete versions.

```yaml
_options:
  version:
    resolution: github_release   # see resolution types below
    default: stable              # default when user omits --version
    inputs: [stable, latest, semver]  # standard proposals to expose
    flag: --version              # flag to query installed version (default)
```

**Resolution types:**

| Type | Queries | Sets `VERSION` to | Sets `_FEAT_RESOLVED_TAG` to |
|------|---------|-------------------|------------------------------|
| `github_release` | GitHub Releases API | Bare version (e.g. `1.7.1`) | Full tag (e.g. `v1.7.1`) |
| `github_tag` | GitHub git tags API | Bare version | Full tag |
| `npm` | npm registry | Package version | (empty) |
| `cargo` | Crates.io API | Crate version | (empty) |
| `git_ref` | `git ls-remote` | Ref name (e.g. `main`) | Resolved SHA |
| `none` | (none) | `VERSION` as given | (empty) |

**`inputs` values** generate standard proposals in the `version` option:

| Value | Generates proposals |
|-------|---------------------|
| `stable` | `stable` — latest final release |
| `latest` | `latest` — latest including pre-releases |
| `semver` | `1`, `1.2`, `1.2.3` examples |
| `npm_tag` | `next`, `beta`, etc. |
| `nvm_alias` | `lts`, `lts/*` |

### `_options.method`

Declares which installation methods the feature supports. Each key enables the corresponding auto-implementation in `install.bash`. **Only declare the methods your feature actually supports.**

```yaml
_options:
  method:
    binary:        # enable __install_run_binary__ auto-impl
      asset_uri: "..."
    package: {}    # enable __install_run_package__ auto-impl
```

The `method` shared option is only injected when at least two methods are declared (otherwise the method is fixed and there's nothing for the user to choose).

**`binary` — download and install a pre-built release binary:**

```yaml
binary:
  asset_uri: "https://github.com/{GH_REPO}/releases/download/{TAG}/tool-{VERSION}-{OS}-{ARCH}.tar.gz"
  sidecar_uri: "https://github.com/{GH_REPO}/releases/download/{TAG}/tool-{VERSION}-{OS}-{ARCH}.tar.gz.sha256"
  binary_src: tool        # filename (suffix-match) inside the archive
```

URI substitutions: `{VERSION}`, `{TAG}`, `{OS}` (`linux`/`darwin`), `{KERNEL}` (`Linux`/`Darwin`), `{ARCH}` (`amd64`/`arm64`), `{OS_ARCH}` (`linux_amd64`), `{PLATFORM}` (`linux/amd64`), `{RUST_TRIPLE}` (`x86_64-unknown-linux-musl`), `{GH_REPO}` (from `_options.gh_repo`).

The auto-implementation handles: URI expansion, fetch, SHA256 verification (from GitHub JSON or sidecar), extraction, binary placement at `${PREFIX}/${bin_dir}/${binary_src##*/}`. Override with `__install_run_binary_pre` / `_FEAT_BINARY_ASSET_PATTERN` for dynamic logic.

**`package` — install via OS package manager:**

```yaml
package:
  manifest: os-pkg        # optional; defaults to "os-pkg"
  registers_as: my-tool   # OS package name for PM version checks (method=auto) and dummy apt registration on non-PM installs
```

Reads `dependencies/run/{manifest}.yaml` (generated from the matching `_dependencies.run` entry). The auto-implementation calls `ospkg__install` with the manifest.

**`upstream-package` — install from the vendor's own OS package repository:**

```yaml
upstream-package:
  registers_as: my-tool   # same dual use as package.registers_as (PM checks + dummy apt registration)
```

Reads `dependencies/run/upstream-package.yaml`. Use when the vendor publishes their own apt/dnf/brew repo.

**`script` — run the tool's own installer script:**

```yaml
script:
  asset_uri: "https://install.tool.sh"
  sidecar_uri: "https://install.tool.sh.sha256"  # optional
  args: ["--yes", "--no-modify-path"]              # static args
```

Fetches the script, optionally verifies checksum, then executes it. Override `_FEAT_INSTALL_SCRIPT_ARGS` in `__install_run_script_pre` for dynamic args.

**`cargo` — install a Rust crate:**

```yaml
cargo:
  crate: my-crate
```

Uses `cargo-binstall` when available (faster), falls back to `cargo install`. Passes `--root ${PREFIX}` and `--version ${VERSION}` automatically.

**`npm` — install a Node.js package globally:**

```yaml
npm:
  package: "@scope/package-name"
  args: []        # default npm install args
```

Runs `npm install -g ${NPM_PACKAGE}@${VERSION}`. Override `NPM_INSTALL_ARGS` for custom flags.

**`npm-bundled` — install an npm package with a self-contained Node.js runtime:**

```yaml
npm-bundled:
  package: "@scope/package-name"
  cmd: tool-binary-name     # binary name created by the package
  node_version: "22"        # or "lts"
```

Bundles its own Node.js installation at `${PREFIX}` — no system Node.js required.

**`source` — build and install from a source tarball:**

```yaml
source:
  asset_uri: "https://github.com/{GH_REPO}/archive/refs/tags/{TAG}.tar.gz"
  build_system: autotools   # autotools | make
  configure_args: ["--with-openssl"]
  make_flags: ["USE_LIBPCRE2=YesPlease"]
  make_targets: ["all", "install"]
```

When `build_system` is set, auto-runs `./configure --prefix=${PREFIX} ${configure_args}` then `make`. Omit `build_system` and define `__install_run_source_build <src_dir>` for custom build logic.

**`git-clone` — clone a Git repository:**

```yaml
git-clone:
  uri: "https://github.com/ohmyzsh/ohmyzsh.git"
  config:
    "core.autocrlf": "false"
```

Clones to `${PREFIX}`, checks out `VERSION` as a ref/branch/SHA. Use `git_ref` for version resolution (resolves branch names to SHAs for change detection).

### `_options.prefix`

Declares where the tool installs and how it becomes available on PATH. Without `_options.prefix`, the feature has no prefix machinery — binaries must be placed and exported manually.

```yaml
_options:
  prefix:
    bins: [tool]                      # binary names to discover and export
    bin_dir: bin                      # subdirectory of PREFIX containing binaries (default: "bin")
    root: /usr/local                  # default prefix when root (default: "/usr/local")
    nonroot: "${HOME}/.local"         # default prefix when non-root
    platform_overrides:               # platform-specific prefix defaults
      - when: {kernel: darwin}
        default: /opt/homebrew
    symlink:
      root: /usr/local/bin            # where to create symlinks when root
      nonroot: "${HOME}/.local/bin"   # where to create symlinks when non-root
      skip: false                     # set true to omit symlink options entirely
    exports:
      skip: false                     # set true to omit PATH-export options
    activation:
      shells: [bash, zsh, fish]       # shells to write activation snippets for
    write_group:
      default: docker                 # group with write access to PREFIX
```

**Auto-generated options** (exposed to users): `prefix`, `prefix_discovery` (`auto | symlink | shell | all | none`), `prefix_bins`, `prefix_bin_dir`, `prefix_symlinks`, `prefix_exports`, `prefix_activations`, `write_group`, `write_users`, `install_user`, `runtime_path`.

**Discovery modes:**

| `prefix_discovery` | Effect |
|--------------------|--------|
| `auto` | If binary already on PATH, skip; otherwise try symlinks, fall back to PATH export |
| `symlink` | Create symlinks only |
| `shell` | Write PATH export to shell profiles only |
| `all` | Both symlinks and PATH export |
| `none` | Skip both |

### `_options.completions`

Declares how to install shell completions. Auto-generates `shell_completions`, `shell_completions_cmd`, `shell_completions_files` options and auto-implements `__install_shell_completions__`.

```yaml
_options:
  completions:
    subcmd: completion --shell   # runs: tool completion --shell bash | zsh | fish ...
    shells: [bash, zsh, fish]    # default shells to install completions for
```

Or for pre-built completion files bundled with the installed tool:

```yaml
_options:
  completions:
    source_files:
      bash: share/bash-completion/completions/tool
      zsh: share/zsh/site-functions/_tool
```

Completions are installed to the standard system or user directories for each shell.

### `_options.verify`

Declares a post-install verification check.

```yaml
_options:
  verify:
    cmd: tool          # binary to run (defaults to primary bin if omitted)
    args: --version    # arguments to pass
    description: "tool --version succeeds"
```

### `_options.installer_dir`

```yaml
_options:
  installer_dir: true
```

When `true`, exposes `installer_dir` user option and sets `INSTALLER_DIR` to a working directory for downloads/extractions. By default a temp dir is used (cleaned up on exit). Set for features where users may want to inspect or persist downloaded artifacts.

### `_options.user_file_fetch`

```yaml
_options:
  user_file_fetch: true
```

When `true`, auto-injects `fetch_headers` (custom HTTP headers) and `fetch_netrc` (`.netrc` path) options. Use for features that accept user-provided URIs that may require authentication.

---

## `_dependencies`

Declare OS packages that must be installed **before** `install.bash` runs. The devcontainer CLI installs these via `ospkg` at image build time.

Manifests are grouped by **lifecycle** (`run`, `build`, …) and **name** (`base`, `os-pkg`, `upstream-package`, …). Sync writes each group to `src/*/dependencies/<lifecycle>/<name>.yaml`.

```yaml
_dependencies:
  run:
    base:
      packages:
        - curl
        - ca-certificates
      apt:
        packages:
          - build-essential
      brew:
        packages:
          - openssl
    os-pkg:
      packages:
        - jq
  build:
    node-gyp:
      packages:
        - python3
```

Full manifest syntax (same format as `lib/ospkg-manifest.schema.json`):

```yaml
# Optional global condition — skips entire manifest if false
when: {pm: apt}

# Signing keys fetched before repos
keys:
  - url: https://example.com/key.gpg
    dest: /usr/share/keyrings/example.gpg

# Repository lines (PM-native format; {deb_arch} etc. substituted at runtime)
repos:
  - content: "deb [arch={deb_arch} signed-by=...] https://repo.example.com stable main"

# Packages for all PMs (or with per-item conditions)
packages:
  - git
  - name: curl
    when: {pm: apt}

# Per-PM package blocks
apt:
  packages:
    - build-essential
brew:
  casks:
    - visual-studio-code

# Shell commands run before/after package installation
prescripts: |
  install -d /opt/myapp
scripts: |
  ldconfig
```

Available `when` keys: `pm` (`apt`, `brew`, `dnf`, `apk`, `yum`, `zypper`, `pacman`), `kernel` (`linux`/`darwin`), `arch`, `deb_arch`, `id`, `id_like`, `version_id`, `version_codename`, and any other `/etc/os-release` field.

The schema is published at `/schema/ospkg-manifest.json` on the docs site. See `.config/proman/docs.yaml` → `json_schemas_publish`.

---

## Other Useful Fields

```yaml
# Container env vars exported to the user's shell after install
containerEnv:
  TOOL_HOME: /opt/tool
  PATH: /opt/tool/bin:${PATH}

# Named volumes for data persistence across container rebuilds
mounts:
  - source: "{localWorkspaceFolderBasename}-tool-cache"
    target: /root/.cache/tool
    type: volume

# Lifecycle commands (run by the devcontainer client after container creation)
onCreateCommand: /path/to/on-create.sh
postStartCommand: /path/to/post-start.sh

# VS Code extensions recommended when this feature is installed
customizations:
  vscode:
    extensions:
      - publisher.extension-id

# Longer description for documentation / help text (not shown in devcontainer UIs)
_long_description: >-
  Detailed prose description used for docs generation.
```

---

## Versioning

Feature versions follow [semver](https://semver.org) (`X.Y.Z`):

| Change type | Bump |
|-------------|------|
| Bug fix, no behaviour change | Patch: `1.2.3` → `1.2.4` |
| New option or capability (backwards-compatible) | Minor: `1.2.3` → `1.3.0` |
| Breaking change to options, defaults, or behaviour | Major: `1.2.3` → `2.0.0` |

CI enforces that any PR touching `features/<id>/` bumps the `version` in that feature's `metadata.yaml`. For changes to `lib/` or `features/install.sh`, all features must be bumped. See {doc}`/dev-guide/devops/ci` for the version-bump guard.

---

## References

- [devcontainer-feature.json upstream schema](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainerFeature.schema.json)
- [Dev Container Feature authoring spec](https://containers.dev/implementors/features/)
- [`features/metadata.schema.json`](../../../../features/metadata.schema.json) — in-repo schema (editor-validated)
- [`features/metadata.shared.yaml`](../../../../features/metadata.shared.yaml) — shared options injected at sync time
- [`lib/ospkg-manifest.schema.json`](../../../../lib/ospkg-manifest.schema.json) — dependency manifest schema
