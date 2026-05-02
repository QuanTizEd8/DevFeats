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



### The bootstrap pattern

The devcontainer specification guarantees only POSIX `sh` is available when
`install.sh` runs. Bash 4+ features used by the library are therefore not
available at that point. The bootstrap pattern resolves this:

- `features/bootstrap.sh` is a POSIX `sh` script. Its only job is to ensure `bash` is
  present and then `exec bash install.bash "$@"`.
- `install.bash` is written in bash ≥4 and uses all library features
  freely.

`features/bootstrap.sh` knows how to install bash on every supported distro (APT, APK,
DNF, microdnf, YUM, Zypper, Pacman). It is the single source of truth — one
copy is distributed to every feature root as `install.sh`.

### The sync mechanism

`scripts/sync-src.py` automates the distribution of shared files:

```
features/bootstrap.sh   →  src/*/install.sh           (one copy per feature)
lib/           →  src/*/_lib/                (one copy per feature)
features/*/install.bash  →  src/*/install.bash  (header prepended)
features/*/metadata.yaml →  src/*/devcontainer-feature.json
features/*/metadata.yaml →  src/*/dependencies/*.yaml
features/*/files/        →  src/*/files/       (copied, not symlinked)
```

It auto-discovers features by finding every `metadata.yaml` under
`features/`. No list is hard-coded.

```bash
# Sync all features
python3 scripts/sync-src.py
# Verify copies are up to date (exits non-zero if stale)
python3 scripts/sync-src.py --check
```

CI runs `python3 scripts/sync-src.py` as the first step of every workflow job to ensure
the working tree is consistent before building or testing.


## Bootstrap pattern

The devcontainer spec guarantees only POSIX `sh` when `install.sh` runs — bash is not guaranteed. The bootstrap resolves this in two steps:

1. **`install.sh`** (POSIX sh) — checks whether `bash` is present; if not, installs it via the system package manager (`apk`, `apt-get`, `dnf`, `microdnf`, `yum`, `zypper`, `pacman`, Homebrew). Then `exec bash install.bash "$@"` to hand off.
2. **`install.bash`** (bash ≥ 4) — the real installer with full access to the shared library.

`install.sh` at each feature root is generated from `features/bootstrap.sh` by `scripts/sync-src.py`. It is identical across all features. **Never write it manually.**
