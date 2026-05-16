## Usage

### Basic

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/devfeats/setup-shim:0": {}
  }
}
```

With the defaults above, all three shims (`code`, `devcontainer-info`,
`systemctl`) are installed.

### Only the `code` shim

```jsonc
{
  "features": {
    "ghcr.io/quantized8/devfeats/setup-shim:0": {
      "devcontainer-info": false,
      "systemctl": false
    }
  }
}
```

---

## How it works

### Shim directory

Shims are installed to `/usr/local/share/QuanTizEd8/DevFeats/setup-shim/bin/`. The feature
declares a `containerEnv` that prepends this directory to `PATH`:

```json
"containerEnv": {
  "PATH": "/usr/local/share/QuanTizEd8/DevFeats/setup-shim/bin:${containerEnv:PATH}"
}
```

This ensures:

- **No collisions** — shims live in their own directory, not alongside other
  files in `/usr/local/bin`.
- **Always highest priority** — the shim directory appears first in `PATH`, so
  shims are found before any real binary of the same name.

### `export_path` option

In addition to `containerEnv`, the feature can persist PATH updates into shell
startup files via the `export_path` option:

- `auto` (default): writes to system-wide shell files when root, or user shell
  files when non-root.
- `""` (empty): skips PATH writes.
- Explicit file list: writes only to those absolute paths.

### Shim scripts

#### `code`

Wrapper for the VS Code CLI. Uses `which -a` to find the next `code` binary
in `PATH` (skipping itself) and execs it. If no `code` is found, falls back
to `code-insiders`. Exits with `127` if neither is available.

#### `devcontainer-info`

Queries dev container image metadata from
`/usr/local/etc/vscode-dev-containers/meta.env` or
`/usr/local/etc/dev-containers/meta.env`. Supports subcommands (`version`,
`release`, `content`) or prints a summary of all available metadata.

#### `systemctl`

Checks whether systemd is running (`/run/systemd/system` exists). If so,
delegates to `/bin/systemctl`. Otherwise, prints a message suggesting the
`service` command as an alternative.
