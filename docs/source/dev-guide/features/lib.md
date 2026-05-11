# Shared Library

The `lib/` directory contains reusable modules (mostly bash) that are sourced by `install.bash` installer scripts. Each module is a file containing related functions that abstract common operations for a specific domain, e.g. OS package installation, GitHub API calls, checksum verification, user management, and shell configuration. During builds, `lib/` is copied into every feature's `src/*/_lib/`, so that `install.bash` can source each module as `$_SELF_DIR/_lib/<module-name>.sh`.

> **Always check here before implementing something from scratch.** If a function does what you need, use it. If you are writing logic that could benefit other features, add it to `lib/` instead of keeping it inline.

## Guard Pattern

To prevent double-sourcing and circular imports, all shell modules must start with an idempotency guard:

```bash
[[ -n "${_MODULE_NAME__LIB_LOADED-}" ]] && return 0
_MODULE_NAME__LIB_LOADED=1
```

Every public function is covered by the bats unit suite under `test/lib/`. Run `just test-lib` to verify changes locally before pushing.

**Multi-value conventions:** many helpers return multiple logical items as one stdout line per item (empty list → no output). This composes naturally with pipes, `while read -r`, and `mapfile`.
