# Feature Options

Each feature declares its options in `metadata.yaml`, which generates the `devcontainer-feature.json` consumed by dev container tooling. The same options are exposed in two matching forms depending on how the feature is invoked.

---

## CLI flags vs environment variables

| Channel | How options are delivered |
|---------|--------------------------|
| Dev Container Features (OCI) | Injected as environment variables by the dev container tooling |
| `install.sh <feature>` (feature mode) | Passed as CLI flags after the feature ID |
| `install.sh <manifest>` (manifest mode) | Extracted from the manifest and injected as environment variables (same as OCI) |
| Direct tarball | Either: set env vars before `sh install.sh`, or pass CLI flags |

The mapping is mechanical: an option named `set_user_shells` in `metadata.yaml` becomes the CLI flag `--set_user_shells` and the environment variable `SET_USER_SHELLS`. Option names are always snake_case; the CLI flag spelling matches the option name verbatim (no hyphenation).

:::{dropdown} Design note: why both modes?

The Dev Containers spec mandates that features be configured via environment variables — tooling gathers them from the `options` object and exports them before invoking `install.sh`. That mode is unergonomic on the CLI (no `--help`, no validation, easy to forget which variable belongs to which feature). By making every installer dual-mode, SysSet keeps full spec compliance while offering a first-class CLI experience. `install.bash` in manifest mode reuses the env-var path exactly, so manifests behave identically to dev container tooling.
:::

---

## Shared options

These options are implemented the same way across every feature:

- **`log_level`** *(string, default `"info"`)* — controls logging verbosity: `silent`, `error`, `warn`, `info`, `debug`, `trace`. Use `trace` to enable `bash -x` tracing inside the installer.
- **`log_file`** *(string, default `""`)* — when set to an absolute path, the installer appends its full captured output to that file on exit (with known secrets redacted).
- **`username`** / **`add_users`** — several features resolve a list of target users from context (`$USER`, `_REMOTE_USER`, detected non-root accounts) and apply per-user configuration. `add_users` lets you include users the feature would otherwise skip.
- **`export_path`** *(array, default `auto`)* — for features that put binaries on `PATH`, this controls which shell startup files receive the export. `auto` does the right thing per platform; a list of absolute file paths targets only those files.

Beyond these, each feature documents its own options on its reference page.

---

## The array type

SysSet extends the standard devcontainer feature option schema with an internal **array** type (serialized as `type: string` in the generated `devcontainer-feature.json`, so spec tooling accepts it). It lets a feature take a list of values ergonomically in every invocation channel.

::::{tab-set}

:::{tab-item} `metadata.yaml`
```yaml
options:
  nerd_fonts:
    type: array
    default: ""      # empty list
    description: Nerd Fonts to install.
    enum:            # optional — each element must match one of these
      - value: Meslo
        description: Meslo LG Nerd Font.
      - value: FiraCode
        description: Fira Code Nerd Font.
```
:::

:::{tab-item} CLI — repeat the flag
```sh
sh install.sh install-fonts \
  --nerd_fonts Meslo \
  --nerd_fonts FiraCode
```
Each `--<flag> <value>` pair **appends** one element to the array.
:::

:::{tab-item} Env var / manifest — newline-delimited
```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-fonts": {
      "nerd_fonts": "Meslo\nFiraCode"
    }
  }
}
```

```sh
NERD_FONTS=$'Meslo\nFiraCode' sh install.sh
```
Values are separated by `\n`; empty lines are ignored.
:::

::::

Inside the installer, the variable is always a bash array, regardless of which channel populated it. Defaults can themselves be multi-line (e.g. `"bash\nzsh"` to default to both shells).
