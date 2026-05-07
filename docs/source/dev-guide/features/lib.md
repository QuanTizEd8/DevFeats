# Shared Library

The `lib/` directory contains reusable POSIX-compliant and Bash-specific files that are sourced by feature installer scripts. They contain functions that abstract common operations, e.g. OS package installation, GitHub API calls, checksum verification, user management, and shell configuration.

## Guard Pattern (lib/ modules only)

All `lib/*.sh` modules must start with an idempotency guard:

```bash
[[ -n "${_MYMODULE__LIB_LOADED-}" ]] && return 0
_MYMODULE__LIB_LOADED=1
```



## Shared library

`lib/` contains the canonical source for the shared helper library, where each file is a module of related functions for a specific domain. These are copied into every feature's `src/*/_lib/`, which are then sourced by the feature scripts.


## Shared library reference

All library files live in `lib/` and are synced to `_lib/` in each feature. Source them from `$_SELF_DIR/_lib/<file>.sh`.

Each module uses a guard variable (`_LIB_<NAME>_LOADED`) to prevent double-sourcing. Every public function is covered by the bats unit suite under `test/lib/`. Run `just test-lib` to verify changes locally before pushing.

**Multi-value conventions:** many helpers return multiple logical items as one stdout line per item (empty list → no output). This composes naturally with pipes, `while read -r`, and `mapfile`.

> **Always check here before implementing something from scratch.** If a function does what you need, use it. If you are writing logic that could benefit other features, add it to `lib/` instead of keeping it inline.
