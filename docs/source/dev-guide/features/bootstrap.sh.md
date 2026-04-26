# Bootstrap Script

The devcontainer spec guarantees only POSIX `sh` when `install.sh` runs —
bash is not guaranteed. The library and installer scripts require bash ≥4.
The bootstrap resolves this two-step:

1. **`install.sh`** (POSIX sh) — checks whether `bash` is present; if not,
   installs it via the system package manager (`apk`, `apt-get`, `dnf`, etc.).
   Then `exec bash install.bash "$@"` to hand off.
2. **`install.bash`** (bash ≥4) — the real installer with full access
   to the shared library.

`install.sh` at the feature root is generated from `features/bootstrap.sh` by
`scripts/sync-src.py`. It is identical in every feature. **Never write it manually.**
