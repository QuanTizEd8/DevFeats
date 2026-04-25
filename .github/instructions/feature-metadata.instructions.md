---
description: "Use when writing or editing feature metadata files. Covers required options, enum vs proposals, versioning, lifecycle commands, and feature ID conventions."
applyTo: "features/**/metadata.yaml"
---

# Feature Metadata Files

Each feature must include a `metadata.yaml` file, containing all metadata about the feature. It is used to generate:
1. `devcontainer-feature.json` files consumed by the devcontainer CLI
2. install script headers (argument parsing, help text, etc),
3. documentation

The JSON Schema is defined in `features/metadata.schema.json`. It is a superset of the [JSON Schema for devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainerFeature.schema.json), with underscored internal-only fields (e.g. `_long_description`, `_dependecies`) added to hold additional metadata.

- Run `just sync` to validate metadata, regenerate all feature files in `src/`, and check for stale files. This runs `scripts/sync-src.py` which handles validation, JSON generation, install script assembly, and file copies.

The `features/derived-options.yaml` file defines shared options that are injected into each feature at sync time. This is useful for options that are common across many features, such as `debug` and `logfile`, so they are not repeated in every metadata file.


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
  ghcr.io/quantized8/sysset/setup-user: {}
```

## Further Reading

- `docs/dev-guide/writing-features.md` — feature anatomy, options, scripts, full library reference


## Key References

- [JSON Schema for devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainerFeature.schema.json)
- [Full JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.schema.json)
- [Core JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.base.schema.json)
