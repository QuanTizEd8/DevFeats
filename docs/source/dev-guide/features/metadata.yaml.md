# Metadata

Each feature must include a `metadata.yaml` file at `features/<feature-id>/metadata.yaml`, following the JSON schema defined in [features/metadata.schema.json](/features/metadata.schema.json). This file contains all metadata about the feature, and is used to generate:
1. `devcontainer-feature.json` files consumed by the devcontainer CLI
2. `install.bash` script headers (argument parsing, help text, sourcing common libraries, etc)
3. dependency manifest files consumed by the [`ospkg`](/lib/ospkg.sh`) library.
4. documentation

The metadata file follows the [JSON schema for devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainerFeature.schema.json), with the following deviations:

- Derivable `devcontainer-feature.json` fields such as `id`, `documentationURL`, and `licenseURL` are explicitly prohibited in the metadata file, and instead generated at sync time. This is to ensure that these fields are consistent across all features, and to avoid duplication and potential inconsistencies in the metadata files.
- Additional internal-only fields are added to the schema to support the generation of install scripts and documentation:
  - `_long_description`: A detailed description of the feature, used for generating documentation and help text.
  - `_dependencies`: Install-time and runtime dependency groups, defined as cross-platform `ospkg` manifests.
- A new `array` option type is added to support options that can accept multiple values, e.g. a list of packages to install. In `devcontainer-feature.json`, this is still represented as a `string` option where the user can input a newline-delimited list of values.

## Options

Each option becomes both a CLI flag (`--<option_name>`) and an environment
variable (`<OPTION_NAME>`) injected by the devcontainer tooling at build time.
Option names use snake_case; the CLI flag uses double-dashes
(`--option_name`).

```jsonc
"options": {
  "version": {
    "type": "string",
    "default": "latest",
    "description": "Version to install."
  },
  "log_level": {
    "type": "string",
    "default": "info",
    "enum": ["silent", "error", "warn", "info", "debug", "trace"],
    "description": "Control log verbosity; use trace for xtrace."
  },
  "mode": {
    "type": "string",
    "default": "fast",
    "enum": ["fast", "safe", "dry_run"],
    "description": "Operating mode."
  }
}
```

Supported types: `"string"`, `"boolean"`, and the DevFeats-internal **`"array"`** type (serialized as `type: string` in the generated JSON). See {doc}`/guide/options` for how the array type works across all invocation channels.

For string options, two properties control how supporting tools (VS Code,
Codespaces) present the allowed values to users:

| Property | Behaviour |
|---|---|
| `"enum"` | **Strict** — the user must choose one of the listed values. Any other value is rejected by the tooling. Use when the script only handles a closed set of values. |
| `"proposals"` | **Suggestive** — the listed values appear as suggestions in the UI, but the user is free to type any value. Use when the script can handle arbitrary input and you only want to provide convenient defaults. |

```yaml
# Closed set — only these three values are accepted
mode:
  type: string
  default: fast
  enum: [fast, safe, dry_run]
  description: Operating mode.

# Open set — suggests common versions; any semver is valid
version:
  type: string
  default: latest
  proposals: [latest, "3.12", "3.11", "3.10"]
  description: Version to install.
```

Always include a `"log_file"` option (string, default `""`). The shared
`"log_level"` option is auto-injected from `features/metadata.shared.yaml`,
so it does not need to be repeated in each feature metadata file.


### Shared Metadata

The `features/metadata.shared.yaml` file defines shared options that are injected into each feature at sync time. This is useful for options that are common across many features, such as `log_level` and `log_file`, so they are not repeated in every metadata file.



## Dependencies

Declare `_dependencies.base` when the installer needs packages (e.g. `curl`, `ca-certificates`) present before any other work begins:

```yaml
_dependencies:
  base:
    packages:
      - ca-certificates
      - curl
```

Manifests are written in YAML. The machine-readable schema is [`lib/ospkg-manifest.schema.json`](../../../../lib/ospkg-manifest.schema.json) in-repo; the same schema is published for editors at `https://<owner>.github.io/<repo>/schema/ospkg-manifest.json` (see `.config/docs.yaml` → `json_schemas_publish`). See the [ospkg manifest instructions](../../../../.github/instructions/ospkg-manifests.instructions.md) for the full authoring reference. A brief overview:

```yaml
# Optional global condition — skips the entire manifest if false
when: {pm: apt}

# Signing keys fetched before repos/packages
keys:
  - url: https://example.com/key.gpg
    dest: /usr/share/keyrings/example.gpg

# Repository lines to add (PM-native format; ${deb_arch} etc. are substituted at runtime)
repos:
  - content: "deb [arch=${deb_arch} signed-by=...] https://repo.example.com stable main"

# Unconditional packages (all PMs)
packages:
  - git
  - name: curl
    when: {pm: apt}
  - name: htop
    version: "3.2.1"

# Per-PM package blocks
apt:
  packages:
    - build-essential
brew:
  casks:
    - visual-studio-code

# Shell commands run before and after package installation
prescripts: |
  install -d /opt/myapp
scripts: |
  ldconfig
```

Available `when` condition keys: `pm` (detected PM: `apt`, `brew`, `dnf`, `apk`, `yum`, `zypper`, `pacman`), `kernel` (`linux`/`darwin`), `arch`, `deb_arch`, `id`, `id_like`, `version_id`, `version_codename`, and any other `/etc/os-release` field.


## Synchronization and Validation

Run `just sync-src` to validate metadata, regenerate all feature files in `src/`, and check for stale files. This runs `scripts/sync-src.py` which handles validation, JSON generation, install script assembly, and file copies.


## Common Patterns

```yaml
# Mount a named volume to persist data across rebuilds
mounts:
  - source: "{localWorkspaceFolderBasename}-cache"
    target: /home/vscode/.cache
    type: volume

# Expose container env vars
containerEnv:
  PATH: /opt/tool/bin:${PATH}

```

## References

- [JSON Schema for devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainerFeature.schema.json)
- [Full JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.schema.json)
- [Core JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.base.schema.json)
