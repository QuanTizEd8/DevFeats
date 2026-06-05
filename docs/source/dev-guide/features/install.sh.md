# `install.sh` (Bootstrap)

The [Dev Container specification](https://containers.dev/implementors/features/#invoking-installsh) requires every feature to have an `install.sh` at its root. Supporting tools set the execute bit on this file and invoke it directly as the feature entry point.

## Purpose

`install.sh` is a minimal POSIX `sh` script — not bash — to ensure it works in any environment, including those where bash is not yet installed. Its only job is to:

1. Ensure `bash` ≥4 is present (installs it via the OS package manager if needed).
2. Hand off execution to `install.bash` (the real installer written in bash ≥4).

## Source of Truth

There is a **single source of truth** at `features/install.sh`. During `just sync-src`, this file is copied verbatim to every `src/*/install.sh`. **Never edit `src/*/install.sh` directly** — it is overwritten on every sync.

To change the bootstrap logic, edit `features/install.sh` and run `just sync-src`.
