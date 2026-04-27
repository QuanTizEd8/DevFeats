---
description: "Use when writing, editing, or creating feature installer scripts under features/**/*.bash or shared library modules under lib/. Covers the bootstrap pattern, library sourcing, logging setup, dual-mode argument parsing, emoji conventions, and the full shared library API."
applyTo: "lib/*.sh"
---

# Shared Library

Read the [Shared Library reference](/docs/source/dev/writing-features.md#shared-library-reference) for detailed information about the conventions, structure, and usage of the shared library modules under `lib/`, and their full API.

The library is synced into each feature as `_lib/` by `scripts/sync-src.py`. Source modules from `$_SELF_DIR/_lib/<module>.sh`. Each module uses a guard variable (`_LIB_<NAME>_LOADED`) to prevent double-sourcing.
