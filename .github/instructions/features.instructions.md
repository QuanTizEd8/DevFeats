---
description: Use when reading and writing feature source files.
applyTo: "features/**/*"
---

# Feature Source Files

## Feature Metadata Files

Read the [`metadata.yaml` reference](/docs/source/dev-guide/features/metadata.yaml.md) for detailed information about the conventions, structure, and usage of the `features/*/metadata.yaml` file for each feature, and their JSON schema defined in `features/metadata.schema.json`.

Shared metadata from `features/metadata.shared.yaml` (`keep_cache`, `keep_build_deps`, `log_file`, `log_level`, …) are injected automatically — do not re-declare them in per-feature `metadata.yaml`.

## Feature Install Scripts

Read the [`install.bash` reference](/docs/source/dev-guide/features/install.bash.md) for detailed information about the conventions, structure, and usage of the `features/*/install.bash` file for each feature.

Key sections:
- [Install script](/docs/source/dev-guide/features/install.bash.md) — template hooks, dispatch order, available env vars
- [Shared library reference](/docs/source/dev-guide/features/lib.md) — full API for all `lib/` modules
