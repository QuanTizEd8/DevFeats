# Feature Options

Features provide a rich set of options to customize their behavior. All options have sensible defaults, so you only need to explicitly set the ones you want to customize.

## Input Modes

Options can be set via different mechanisms depending on the installation method, but they all share the same names and semantics across channels.

### Dev Container

In Dev Containers, each feature's options are defined in the `devcontainer.json` file's `features.<feature-id>.options` object – the value of the feature ID key in the `features` object. The dev container tooling automatically gathers these options and injects them as environment variables when invoking the feature's installer script.

```jsonc
{
  // devcontainer.json
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user": {
      "username": "myusername",
      "user_id": "1000"
    }
  }
}
```

### CLI

When using SysSet or invoking the installer script directly, options can be passed as CLI flags with the form `--<option_name> <value>`, passed after the feature ID. The CLI flag spelling matches the option name verbatim (no hyphenation):

```sh
# Using SysSet:
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user \
  --username myusername \
  --user_id 1000

# Directly invoking the installer:
sh install.sh setup-user \
  --username myusername \
  --user_id 1000
```

:::{admonition} Environment Variables
:class: note dropdown

To be Dev Container Feature compliant, all features also support reading options from environment variables, which is how dev container tooling delivers them. Environment variables take the form `<OPTION_NAME>=<value>` and are set before invoking the installer:

```sh
USERNAME=myusername \
USER_ID=1000 \
sh install.sh setup-user
```

However, this type of delivery is discouraged outside of dev container features, as it is more error-prone (e.g. an unrelated existing environment variable with the same name as a feature option can cause unintended configuration). Therefore, to avoid unexpected interactions, features only read options from environment variables when no CLI flags are provided at all. Even a single CLI flag for any option will disable environment variable parsing for all options in that invocation, causing any options not explicitly set via CLI flags to fall back to their defaults.
:::


## Option Types

Each option has one of the following types, which determines how it is set in each channel and how the installer receives it. The type of each option is documented on its reference page.

### String

String options take a single arbitrary string value. Depending on the context, the string may be interpreted as a literal value (e.g. a username), or parsed according to some rules (e.g. a version string that accepts `latest` and semver ranges); it may also contain special characters and whitespace (e.g. a multi-line shell command).

::::{tab-set}

:::{tab-item} Dev Container
```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git": {
      "version": "2.54.0"
    }
  }
}
```
:::

:::{tab-item} CLI

```sh
sh install.sh install-git \
  --version "2.54.0"
```
:::

:::{tab-item} Env Var

```sh
VERSION="2.54.0" sh install.sh install-git
```
:::

::::


### Enum

Enum options are just like string options, but their allowed values are constrained to a specific set (e.g. `log_level` can only be `silent`, `error`, `warn`, `info`, `debug`, or `trace`).

### Boolean

Boolean options are flags that can be either `true` or `false`.

::::{tab-set}

:::{tab-item} Dev Container
```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell": {
      "install_direnv": true
    }
  }
}
```
:::

:::{tab-item} CLI

```sh
sh install.sh install-shell \
  --install_direnv true
```
:::

:::{tab-item} Env Var

```sh
INSTALL_DIRENV=true sh install.sh install-shell
```
:::

::::

### Array

SysSet extends the standard devcontainer feature option schema with an internal **array** type (serialized as `string` in the generated `devcontainer-feature.json`, so spec tooling accepts it). It lets a feature take a list of values ergonomically in every invocation channel. Array elements can be either strings or enums. Some options of this type also support single sentinel values (e.g. `auto`) that resolves to a default array based on the context. An empty string input corresponds to an empty array. Inside the installer, the variable is always a bash array, regardless of which channel populated it.

::::{tab-set}

:::{tab-item} Dev Container

Since `devcontainer.json` only supports string and boolean types, array options are represented as multi-line strings with newline-delimited values (with leading/trailing whitespace trimmed and empty lines ignored).

```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-fonts": {
      "nerd_fonts": "Meslo\nFiraCode"
    }
  }
}
```
:::

:::{tab-item} CLI

In the CLI, array options are set by repeating the corresponding flag for each element (each `--<flag> <value>` pair **appends** one element to the array):

```sh
sh install.sh install-fonts \
  --nerd_fonts Meslo \
  --nerd_fonts FiraCode
```
:::

:::{tab-item} Env Var

Similarly to `devcontainer.json`, array option can be set via environment variable by using a newline-delimited string. In bash, this can be done with ANSI-C quoting (`$'...'`):

```sh
NERD_FONTS=$'Meslo\nFiraCode' sh install.sh install-fonts
```

In POSIX shells that don't support ANSI-C quoting, you can use a literal multi-line string:

```sh
NERD_FONTS="Meslo
FiraCode" sh install.sh install-fonts
```
:::

::::


## Common Options

Some options are shared across features, such as logging-related options, cache configuration, authentication options, user configuration, version specification, installation method, and more. These appear in each feature's reference page, with the same names and semantics, so you can rely on them working the same way in every feature that supports them.

### Logging

All features support emitting logs to the console (stderr) and/or to a file, with configurable verbosity (and known secrets redacted). Log lines are prefixed with emojis to indicate their level (grep for `❌` / `⛔` in a log file to jump straight to failures.). The logging is controlled by three options that are supported across all features:

- **`log_level`** *(string, default `"info"`)* — controls logging verbosity for the console (stderr). Levels are, in increasing order of verbosity:
  - `silent`: only fatal errors (❌)
  - `error`: above plus non-fatal errors (⛔)
  - `warn`: above plus warnings (⚠️)
  - `info`: above plus general info (ℹ️)
  - `debug`: above plus debug messages (🐞)
  - `trace`: above plus `bash -x` tracing inside the installer
- **`log_file`** *(string, default `""`)* — when set to a file path, all logs are also captured to that file in addition to the console. The file receives the same log lines as the console, but filtered by `log_file_level` instead of `log_level`, so you can have verbose logs in the file and a quieter console output. Append-safe; works across features in the same run.
- **`log_file_level`** *(string, default `"debug"`)* — controls the minimum log level captured in the log file specified by `log_file`. Same levels as `log_level`.

### Caching

All features provide a `keep_cache` boolean option that controls whether package manager caches are kept after installation (e.g. `apt` cache on Debian-based systems, `dnf` cache on RedHat-based systems, `conda` cache when using Conda). This is `false` by default to save disk space and keep image layers smaller, but can be set to `true` when you want to keep the cache for faster subsequent installs or when installing outside of a container where layer size is not a concern.

### Build Tools

Most features depend on tools to download files (e.g. `curl`, `wget`, `git`), extract archives (e.g. `tar`, `unzip`), parse JSON API responses (e.g. `jq`), build from source (e.g. `make`, `cmake`), and more. These are not runtime dependencies of the installed features, but they are required to perform the installation. By default, the installer attempts to detect which tools are available in the environment and use them accordingly. If any required tool is missing, the installer will install it automatically and mark it for removal at the end of the installation to avoid leaving unnecessary packages on the system. However, you can also choose to keep them by setting `keep_build_tools` to `true`. This is useful to speed up subsequent installs of other features that use the same tools, at the cost of leaving them on the system.


## Secrets

Some features support options that are secrets (e.g. tokens, passwords, private keys). These are always only accepted via environment variables, regardless of the installation channel, and are always masked in the captured log stream. They include:

- `GITHUB_TOKEN` *(optional)*: If set, used to authenticate GitHub API calls (avoids anonymous rate limits).

::::{tab-set}

:::{tab-item} Dev Container

```jsonc
{
  "build": {
    "dockerfile": "Dockerfile",
    "args": { "GITHUB_TOKEN": "${localEnv:GITHUB_TOKEN}" }
  },
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-miniforge": {
      "version": "26.1.1-3"
    }
  }
}
```
:::

:::{tab-item} Env Var


```sh
GITHUB_TOKEN=ghp_1234567890abcdef \
sh install.sh install-miniforge \
  --version 26.1.1-3
```
:::

::::
