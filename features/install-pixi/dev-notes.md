# Implementation Reference

## Summary

The installer downloads a pre-built static binary from GitHub Releases, verifies it
against a `.tar.gz.sha256` sidecar file, extracts it to `$PREFIX/bin`, and optionally updates
shell startup files for PATH and completion. It follows the same structural patterns
as `src/install-miniforge/install.bash`.

All heavy-lifting is delegated to `lib/` functions. The installer's own functions
are pure orchestrators that handle pixi-specific logic (triple detection, version
stripping, self-update invocation) while the shared library handles downloads,
checksums, shell config writes, OS packages, and logging.


### NETRC Download Handling

When `NETRC` is non-empty, the installer cannot use `net__fetch_url_file` directly
(which has no netrc support). Instead, `download_pixi` falls back to an inline
`curl --netrc-file "$NETRC"` (or `wget --netrc-file "$NETRC"`) call for
the archive download. The sidecar (`.tar.gz.sha256`) does not contain secrets and is
fetched with `net__fetch_url_file` even when `NETRC` is set, unless a netrc-protected
mirror delivers both.

Implementation detail: detect preferred tool via `command -v curl` / `command -v wget`
—same logic used in `net.bash`—so we don't duplicate tool detection.

### Version-Match Idempotency

The version-match short-circuit check is performed **before** any download attempt:

```bash
_installed_ver="$(get_installed_version)"
if [[ -n "$_installed_ver" && "$_installed_ver" == "$VERSION" ]]; then
  echo "ℹ️ Installed pixi version '${_installed_ver}' matches '${VERSION}'. Skipping install."
  _SKIP_INSTALL=true
fi
```

This is intentionally placed before the `handle_if_exists` call to avoid
unnecessary downloads.

### riscv64 Triple

Linux RISC-V uses `riscv64gc-unknown-linux-gnu` (GNU libc), **not** musl. This is
the only Linux triple that uses GNU libc; all others use musl. The `detect_triple`
function must explicitly handle this case by matching `riscv64` from `uname -m`.

### PREFIX Auto-Resolution and root vs non-root

`resolve_bin_dir` runs immediately after argument defaults are applied and before any
other path-based logic:

```bash
if [ "${PREFIX}" = "auto" ]; then
  [ "$(id -u)" = "0" ] && PREFIX="/usr/local" || PREFIX="${HOME}/.pixi"
elif [ -z "${PREFIX}" ]; then
  PREFIX="${HOME}/.pixi"
fi
```

This mirrors the `prefix="auto"` pattern in `install-git`. The resolved value feeds
`check_root_requirement`, `handle_if_exists`, the symlink logic, and `export_path_main`.

### Post-Install Verification

`verify_installed_binary` runs after both the install path and the `if_exists=skip/update`
pass-through paths. It uses a two-step fallback to avoid spurious failures when pixi is
recognised by PATH but sits at a different location than the resolved `$PREFIX`:

```bash
if "${PREFIX}/bin/pixi" --version > /dev/null 2>&1; then
  "${PREFIX}/bin/pixi" --version
elif command -v pixi > /dev/null 2>&1; then
  pixi --version
else
  echo "⛔ pixi not found at '${PREFIX}/bin/pixi' and not on PATH." >&2
  exit 1
fi
```

This matches `set_executable_paths --verify` in `install-miniforge`.

### PIXI_HOME Export

`export_pixi_home_main` runs unconditionally but is a fast no-op when `HOME_DIR` is empty (the default). When `home_dir` is set, pixi reads `PIXI_HOME` on every invocation to locate global environments and config; skipping the export means a custom `home_dir` is silently ignored at runtime.

The file targeting follows the same root/non-root split as `export_path_main`, using a separate `profile_d` stub (`pixi_home.sh`) so both stubs coexist cleanly under `/etc/profile.d/`.

### PATH Export: skip when PREFIX is already on PATH

When `EXPORT_PATH="auto"` and `PREFIX="/usr/local"`, `export_path_main` skips
all writes and logs:

```
ℹ️ PREFIX is /usr/local; /usr/local/bin is already on PATH in all container images; skipping PATH write.
```

This avoids modifying `/etc/profile.d/` and system bashrc/zshenv for a no-op. If the
user explicitly supplies a file list (non-`auto` value), the write happens regardless —
they are asking for it explicitly.

### Symlink: canonical bin directory, non-standard prefix only

`create_symlink` creates a symlink from the canonical bin directory to `$PREFIX/bin/pixi` only
when `SYMLINK=true` and `PREFIX` differs from the canonical path:

- Root: `/usr/local/bin/pixi → $PREFIX/bin/pixi` when `PREFIX ≠ /usr/local`.
- Non-root: `$HOME/.pixi/bin/pixi → $PREFIX/bin/pixi` when `PREFIX ≠ $HOME/.pixi`
  (`$HOME/.pixi/bin` is created if needed).

This is a no-op for the default case (`prefix=auto` → canonical path) since no symlink
is needed when the binary is already in the right location.

### Cleanup Safety

The `__cleanup__` EXIT trap always runs `logging__cleanup`. Installer file cleanup is
handled inside `github__install_release`: when `installer_dir` is empty (default), a
private tmpdir is created via `file__mktmpdir` and auto-cleaned at exit; when
`installer_dir` is set to a non-empty path, that directory and all its contents
(archive, sidecar, etc.) are preserved after installation completes.

---

## References

- [Installation Reference](./installation.md) — research output; installation methods and decision.
- [API Reference](./api.md) — feature option design.
- [install-miniforge/install.bash](../../src/install-miniforge/install.bash) — reference pattern for dual-mode parsing, export_path_main, cleanup, if_exists logic.
- [install-git/install.bash](../../src/install-git/install.bash) — reference pattern for `prefix="auto"` root/non-root resolution and `create_symlink` (steps 1 and 8).
- [lib/shell.bash](../../lib/shell.bash) — `shell__sync_block`, `shell__system_path_files`, `shell__user_path_files`, `shell__detect_bashrc`, `shell__detect_zshdir`.
- [lib/verify.bash](../../lib/verify.bash) — `verify__sha_sidecar`.
- [lib/github.bash](../../lib/github.bash) — `github__latest_tag`.
- [lib/net.bash](../../lib/net.bash) — `net__fetch_url_file`.
- [lib/os.bash](../../lib/os.bash) — `os__kernel`, `os__arch`, `os__require_root`.
- [Pixi Installation Reference Docs](https://pixi.prefix.dev/latest/installation/) — official env var list.
- [Pixi self-update CLI Docs](https://pixi.prefix.dev/latest/reference/cli/self-update/) — `pixi self-update --version X.Y.Z` (no `v` prefix).
