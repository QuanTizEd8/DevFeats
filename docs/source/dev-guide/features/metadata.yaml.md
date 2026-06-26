# `metadata.yaml`

`features/<feature-id>/metadata.yaml` is the primary source of truth for a feature. It drives:

1. `src/*/devcontainer-feature.json` — the OCI-compliant feature spec consumed by the devcontainer CLI
2. `src/*/install.bash` header — argument parsing, env var injection, library sourcing, option validation
3. Documentation — options table and examples on the feature's reference page

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
      binary_src:
        - tool
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
- Shared `method=auto` resolution from the declared methods and their `when` blocks
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

**Minimal declaration** — for the vast majority of features only `resolution` is required:

```yaml
_options:
  version:
    resolution: github_release
```

Everything else has a sensible default: `default` is `stable`, `flag` is `--version`, and proposals are auto-generated from the resolution type. Only declare the other keys when you need to override a default.

**Resolution types:**

| Type | Queries | Sets `VERSION` to | Sets `_FEAT_RESOLVED_TAG` to |
|------|---------|-------------------|------------------------------|
| `github_release` | GitHub Releases API | Bare version (e.g. `1.7.1`) | Full tag (e.g. `v1.7.1`) |
| `github_tag` | GitHub git tags API | Bare version | Full tag |
| `npm` | npm registry | Package version | (empty) |
| `cargo` | Crates.io API | Crate version | (empty) |
| `git_ref` | `git ls-remote` | Ref name (e.g. `main`) | Resolved SHA |
| `sidecar` | Downloaded checksum file | Bare version | (empty) |
| `none` | (none) | `VERSION` as given | (empty) |

**Optional keys and their defaults:**

| Key | Default | Override when… |
|-----|---------|---------------|
| `default` | `stable` | The tool's natural default is not `stable` (e.g. `lts/*` for Node.js, `master` for git-cloned repos) |
| `flag` | `--version` | The tool reports its version differently (e.g. `version` as a subcommand) |
| `uri` | auto-derived from `gh_repo` | `resolution: sidecar` — URL of the checksum file |
| `pattern` | (required for sidecar) | `resolution: sidecar` — filename pattern, e.g. `zsh-[version].tar.xz` |
| `description` | auto-generated per resolution type | `resolution: none` — the tool has a unique versioning scheme the generic description doesn't capture |
| `inputs` | (none) | `resolution: none` only — declares which standard proposal types to auto-generate |
| `proposals` | (none) | `resolution: none` only — adds proposals in tool-unique formats not covered by `inputs` |

**Auto-generated proposals**: for every resolution type except `none`, the `version` user option automatically receives proposals covering all accepted input formats (`stable`, `latest`, semver prefix examples, and type-specific aliases like `next` for npm or `master`/`v1.0.0` for git refs). **Do not declare `inputs` or `proposals` on these features** — `inputs` is schema-invalid on non-`none` features, and `proposals` has no effect.

**`none`-resolution features** receive no auto-generated proposals. Use `inputs` and/or `description` to document what the custom resolver accepts:

```yaml
_options:
  version:
    resolution: none
    default: lts/*
    inputs: [nvm_alias, stable, latest, semver]
    description: >-
      Node.js version to install. Accepts: `stable`, `lts`/`lts/*`, `latest`,
      a major number (e.g. `22`), a major.minor (e.g. `22.1`), or an exact semver.
```

For tools with entirely tool-specific version formats (like TeX Live's year-based snapshots), use `proposals` instead of `inputs`:

```yaml
_options:
  version:
    resolution: none
    default: latest
    description: >-
      TeX Live version to install. Accepts: `stable`, `latest`, a 4-digit year, or a date.
    proposals:
      - value: stable
        description: Most recent annual TeX Live release (frozen snapshot).
      - value: latest
        description: Live CTAN mirror pool — always the most current packages.
      - value: '2026'
        description: TeX Live 2026 frozen snapshot.
```

**`inputs` values** (only for `resolution: none`):

| Value | Generates proposals |
|-------|---------------------|
| `stable` | `stable` — latest final release |
| `latest` | `latest` — latest including pre-releases |
| `semver` | `1`, `1.2`, `1.2.3`, `1.2.3-rc1`, `1.2.3+build.1` format examples |
| `nvm_alias` | `lts/*`, `lts` |

**`proposals`** should only contain values whose format is not already covered by `inputs` or the resolution type's auto-generated entries. Do not add semver-format pinned versions (e.g. `1.7.1`) — the auto-generated `1.2.3` example already communicates that format.

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
  asset_uri: "https://github.com/{GH_REPO}/releases/download/{feat.tag}/tool-{feat.version}-{plat.kernel:lower}-{plat.machine_release}.tar.gz"
  sidecar_uri: "https://github.com/{GH_REPO}/releases/download/{feat.tag}/tool-{feat.version}-{plat.kernel:lower}-{plat.machine_release}.tar.gz.sha256"
  binary_src:             # source path(s) inside the archive (suffix-match)
    - tool                # one entry: single binary; multiple entries: fan-out copies
```

URI substitutions use qualified context tokens expanded by `ctx__expand_pattern` — see [Unified condition context](context.md). Common tokens: `{feat.version}`, `{feat.tag}`, `{plat.kernel:lower}`, `{plat.machine_release}`, `{plat.rust_triple}`, `{GH_REPO}` (from `_options.gh_repo`).

The auto-implementation handles: URI expansion, fetch, SHA256 verification (from GitHub JSON or sidecar), extraction, and binary placement. A single `binary_src` entry installs to `${PREFIX}/bin/<basename>`; multiple entries install real copies into `${PREFIX}/bin/` via fan-out (use `companion_bins` for symlinks to the primary binary only). Override with `__install_run_binary_pre` only when the asset URI or verification logic must be computed dynamically.

**`package` — install via OS package manager:**

```yaml
package:
  registers_as: my-tool   # OS package name for PM version checks (method=auto) and dummy apt registration on non-PM installs
```

Installs packages from `_dependencies.run.method-package` via the generated `ospkg_manifest_method_package_run` option (override with inline YAML or a path/URI).

**`upstream-package` — install from the vendor's own OS package repository:**

```yaml
upstream-package:
  registers_as: my-tool   # same dual use as package.registers_as (PM checks + dummy apt registration)
```

Installs packages from `_dependencies.run.method-upstream-package` via `ospkg_manifest_method_upstream_package_run`.

**`source` — build from a source archive:**

```yaml
source:
  asset_uri: "https://github.com/{GH_REPO}/archive/refs/tags/{feat.tag}.tar.gz"
  sidecar_uri: "https://github.com/{GH_REPO}/releases/download/{feat.tag}/sha256sums.txt"
  build_system: make              # or: autotools
  build_env:                      # optional: exported during auto-build
    - GOTOOLCHAIN=auto
  make_targets: ["all"]           # optional; defaults to ["all", "install"]
  install_bins:                   # optional: copy built artifacts after auto-build
    - bin/tool
```

The source auto-implementation handles: archive download, optional sidecar verification, extraction, and the declared auto-build flow:

- `build_system: autotools` → `./configure --prefix="${PREFIX}"` then `make`
- `build_system: make` → `make` only

Use `build_env` for exported build-time environment variables that must be visible to `./configure` and/or `make`. Use `make_targets` / `make_flags` / `configure_args` when upstream already exposes a suitable install target. Use `install_bins` when upstream builds binaries but does not provide an install step; each listed path is copied from the extracted source tree into `${PREFIX}/bin/<basename>` after the auto-build succeeds. Only define `__install_run_source_build` when the build/install process cannot be expressed with those declarative controls.

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

### `_options.configure_users`

```yaml
_options:
  configure_users: true
```

When `true`:

1. Auto-injects four user-resolution options: `add_current_user`, `add_remote_user`, `add_container_user`, and `add_users`. These let the user control which accounts the feature configures at install time.
2. Auto-calls `__feat_do_configure_users__` at the end of `__install_finish__` and in the `if_exists=skip` branch — no manual hook needed.

The feature must define `__configure_user <username>` in `install.bash` to implement the per-user logic. See [`__configure_user`](install.bash.md#__configure_user-username----per-user-configuration) in the install.bash reference.

---

## `_dependencies`

Declare OS package dependencies installed by the template dependency dispatcher during `install.bash`. During metadata load, each group is emitted as a generated **`ospkg_manifest_*` option** (multiline YAML default in `devcontainer-feature.json`) via pyserials in `metadata.shared.yaml`; users can override the value in `devcontainer.json`.

Manifest groups use three prefixes:

| Key prefix | Example | Generated option(s) | Lifecycles |
|------------|---------|---------------------|------------|
| `base` | `base` | `ospkg_manifest_base_{run\|build}` | `run`, `build` |
| `method-*` | `method-package` | `ospkg_manifest_method_{method}_{run\|build}` | `run`, `build` |
| `option-*` | `option-archive_tools` | `ospkg_manifest_option_{name}` | `run` only |

```yaml
_dependencies:
  run:
    base:
      packages:
        - curl
        - ca-certificates
    method-package:
      packages:
        - jq
    option-node_gyp_deps:
      packages:
        - make
  build:
    method-source:
      packages:
        - build-essential
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

Option-bound groups (`option-*`) with a matching boolean user option are installed automatically at the start of `__install_run__` (after options are parsed). Use manifest `when` clauses — not feature hooks — to skip installs on specific platforms (e.g. exclude Alpine for node-gyp deps).

### Dependency manifest codegen

| Rule | Rationale |
|------|-----------|
| Generated `ospkg_manifest_*` user options live in [`metadata.shared.yaml`](../../../features/metadata.shared.yaml) via pyserials mapping-unpack | Single visible definition; no hidden post-fill injection |
| Python post-fill in `MetadataLoader` is forbidden for option emission | Keeps codegen in one auditable place |
| Pyserials mapping-unpack placeholder keys in `options` must survive `_filter_options` until `TemplateFiller.fill` | Shared metadata uses a dict-key unpack marker, not a normal option dict |
| `option-*` manifest groups belong under `_dependencies.run` only | Option-bound installs run once at the start of `__install_run__` |
| `method-*` keys must match a declared `_options.method` contract key | Enforced by schema (`patternProperties` + root `allOf` if/then rules) |
| Shared library code must not contain feature/option name literals for behavior | Generic algorithms over metadata shape only |
| Spike/integration tests in `test/proman/test_metadata.py` required for codegen changes | Catches regressions at load time |

During `install.bash`, boolean option-bound manifests install once at the start of `__install_run__` (both methodful and method-less features). Features that fully override `__install_run__` must call `__dep_install_option_bound__` once at the top themselves.

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
