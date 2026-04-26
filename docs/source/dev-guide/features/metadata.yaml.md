# Metadata

Each feature must include a `metadata.yaml` file, following the JSON schema defined in [features/metadata.schema.json](/features/metadata.schema.json). This file contains all metadata about the feature, and is used to generate
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

Supported types: `"string"`, `"boolean"`.

For string options, two properties control how supporting tools (VS Code,
Codespaces) present the allowed values to users:

| Property | Behaviour |
|---|---|
| `"enum"` | **Strict** — the user must choose one of the listed values. Any other value is rejected by the tooling. Use when the script only handles a closed set of values. |
| `"proposals"` | **Suggestive** — the listed values appear as suggestions in the UI, but the user is free to type any value. Use when the script can handle arbitrary input and you only want to provide convenient defaults. |

```jsonc
// Closed set — only these three values are accepted
"mode": {
  "type": "string",
  "default": "fast",
  "enum": ["fast", "safe", "dry_run"],
  "description": "Operating mode."
}

// Open set — suggests common versions, but any semver is valid
"version": {
  "type": "string",
  "default": "latest",
  "proposals": ["latest", "3.12", "3.11", "3.10"],
  "description": "Version to install."
}
```

Always include a `"log_file"` option (string, default `""`). The shared
`"log_level"` option is auto-injected from `features/shared-options.yaml`,
so it does not need to be repeated in each feature metadata file.




### Shared Options

The `features/shared-options.yaml` file defines shared options that are injected into each feature at sync time. This is useful for options that are common across many features, such as `log_level` and `log_file`, so they are not repeated in every metadata file.


## Synchronization and Validation

Run `just sync` to validate metadata, regenerate all feature files in `src/`, and check for stale files. This runs `scripts/sync-src.py` which handles validation, JSON generation, install script assembly, and file copies.


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

# Declare feature dependencies
dependsOn:
  ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user: {}
```

### Dependencies on other features

If your feature needs another feature to have already run at build time
(e.g. it calls `install-os-pkg`), declare it with `"dependsOn"`:

```yaml
dependsOn:
  ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user: {}
```
The devcontainer CLI resolves the installation order automatically.



## Key References

- [JSON Schema for devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainerFeature.schema.json)
- [Full JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.schema.json)
- [Core JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.base.schema.json)
