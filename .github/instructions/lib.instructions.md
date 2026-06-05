---
description: "Use when writing, editing, or creating feature installer scripts under features/**/*.bash or shared library modules under lib/. Covers the bootstrap pattern, library sourcing, logging setup, dual-mode argument parsing, emoji conventions, and the full shared library API."
applyTo: "lib/**/*"
---

# Shared Library

The `lib/` directory contains shared library modules that provide common functionality for feature installer scripts under `features/*/install.bash`. These modules are sourced by the install scripts to access the shared library API, which includes utilities for logging, argument parsing, caching, and more.
The library is synced into each feature as `_lib/`, and scripts source them from `$_BASE_DIR/_lib/<module>.sh`.

Read the [Shared Library reference](/docs/source/dev-guide/features/lib.md) for detailed information about the conventions, structure, and usage of the shared library modules under `lib/`, and their full API.
