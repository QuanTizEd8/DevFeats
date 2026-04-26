---
description: "Use when reading and writing feature metadata files."
applyTo: "features/**/metadata.yaml, features/metadata.schema.json"
---

# Feature Metadata Files

Read the [Feature Metadata documentation](/docs/source/dev-guide/features/metadata.yaml.md) for detailed information about the conventions, structure, and usage of the `features/*/metadata.yaml` file for each feature, and their JSON schema defined in `features/metadata.schema.json`.

Derived options from `features/shared-options.yaml` (`keep_cache`, `keep_build_deps`, `log_file`, `log_level`, …) are injected automatically — do not re-declare them in per-feature `metadata.yaml`.
