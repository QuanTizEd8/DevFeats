## Configuration files

The feature deploys a two-tier configuration architecture: **system-wide**
files in `/etc/` that establish sane defaults for all users, and
**per-user** dotfiles (skel templates) in each user's home directory.

### Design principles

1. **POSIX-first, shell-specific second.** Shared logic lives in
   `/etc/shellenv` and `/etc/shellrc` (POSIX sh), sourced by both Bash and
   Zsh. Shell-specific files delegate to these shared files, then add only
   what is unique to that shell.

2. **One-write pattern.** Environment variables (`PATH`, `XDG_*`, locale,
   editor) are set once in `/etc/shellenv` with a sentinel guard
   (`_SHELLENV_LOADED`), so they are never recomputed regardless of how many
   config files source it.

3. **Theme scaffold files.** Empty `$ZDOTDIR/zshtheme` and
   `~/.config/bash/bashtheme` files are created as scaffolds for downstream
   features (e.g. `install-ohmyzsh`, `install-starship`). These features
   append their own guarded blocks via `shell__write_block`. The skel
   `.zshrc` / `.bashrc` source them unconditionally, so they must exist
   before the first interactive session.

4. **Non-interactive non-login coverage.** `BASH_ENV` is set in
   `/etc/environment` so that VS Code tasks, `devcontainer exec`, CI runners,
   and other non-interactive non-login Bash sessions source the environment.

### System-wide files

| Destination | Source | Purpose |
|---|---|---|
| `/etc/shellenv` | `files/shell/shellenv` | POSIX environment: `extend_path` helper, `PATH`, `XDG_*`, locale, umask, default editor. Sourced by `/etc/profile` (sh/bash login) and `/etc/zsh/zshenv` (all zsh). |
| `/etc/shellrc` | `files/shell/shellrc` | Shared interactive config: `GPG_TTY`, VS Code editor integration, `dircolors`, `lesspipe`, `GCC_COLORS`, `command-not-found` handler. Sourced by both bashrc and zshrc. |
| `/etc/shellaliases` | `files/shell/shellaliases` | Shared aliases (`ll`, `la`, `l`). Sourced by `/etc/shellrc`. |
| `/etc/profile` | `files/profile` | Login shell profile for sh/bash. Sources `/etc/shellenv`, runs `/etc/profile.d/*.sh`, and for interactive bash sources the system bashrc. |
| `/etc/bash.bashrc`\* | `files/bash/bashrc` | Bash interactive config: prompt (`PS1`), history (append, deduplicate, timestamps), `shopt` settings, bash-completion. Sources `/etc/shellrc`. |
| `/etc/bash/bashenv`\* | `files/bash/bashenv` | Bash non-interactive environment. Sources `/etc/shellenv`. Pointed to by `BASH_ENV` in `/etc/environment`. |
| `/etc/zsh/zshenv`\* | `files/zsh/zshenv` | Sources `/etc/shellenv` via `emulate sh`. Runs for every zsh invocation. |
| `/etc/zsh/zprofile`\* | `files/zsh/zprofile` | Sources `/etc/profile` via `emulate sh`. Runs for zsh login shells. |
| `/etc/zsh/zshrc`\* | `files/zsh/zshrc` | Zsh interactive config: key bindings (terminfo-based), completion styles (`zstyle`), `compinit`, `run-help`, history settings, `COMBINING_CHARS`. Sources `/etc/shellrc`. |

\* Exact path varies by distribution — see [System path detection](#system-path-detection).

### Per-user skel files

These are copied from `files/skel/` to each configured user's home directory.

| Skel file | Deployed location | Purpose |
|---|---|---|
| `.shellenv` | `~/` | User environment variables and `PATH` additions. Sourced by `.zshenv` and `.bash_profile`. Has a sentinel guard to prevent double-sourcing. Sets `XDG_*` directories. |
| `.shellrc` | `~/` | User interactive config shared across bash and zsh (aliases, functions, cross-shell tool initialisers). |
| `.bash_profile` | `~/` | Login shell setup for bash (and zsh via `.zprofile`). Sources `.shellenv`, then `.bashrc` (guarded by `$BASH`). |
| `.bashrc` | `~/` | Bash interactive config. Sources `~/.config/bash/bashtheme` (theme scaffold) then `.shellrc`. |
| `.zshenv` | `~/` | Delegates to `.shellenv` via `emulate sh`. Has `ZDOTDIR` injected dynamically (see [ZDOTDIR](#zdotdir)). Must live in `$HOME` so Zsh can find it before `ZDOTDIR` is set. |
| `.zprofile` | `$ZDOTDIR/` | Delegates to `.bash_profile` via `emulate sh` for unified login setup. |
| `.zshrc` | `$ZDOTDIR/` | Zsh interactive config. Sources `$ZDOTDIR/zshtheme` (theme scaffold) then `.shellrc`. |
| `.zlogin` | `$ZDOTDIR/` | Runs after `.zshrc` for login shells. Empty by default — suitable for login announcements. |

### Theme scaffold files

`$ZDOTDIR/zshtheme` and `~/.config/bash/bashtheme` are created as empty
files during user configuration. Downstream features append their managed
configuration blocks to these files using `shell__write_block`. The skel
`.zshrc` and `.bashrc` source them unconditionally — they must exist before
the first interactive session.

If the scaffold files already exist (e.g. from a downstream feature), they
are left untouched by setup-shell.

### `if_exists` behavior

The `if_exists` option controls how existing per-user dotfiles are handled
during re-runs. It has no effect on the initial install.

| Value | Per-user dotfile behavior |
|---|---|
| `skip` (default) | Create each file if absent; leave it untouched if it already exists |
| `update` | Sync managed blocks in place; append block if not yet present |
| `reinstall` | Delete existing file and recreate with managed-block content |
| `uninstall` | Remove managed blocks; delete file if it becomes empty |

### ZDOTDIR

By default Zsh looks for per-user config files (`.zshrc`, `.zprofile`,
`.zlogin`) in `$ZDOTDIR`. This feature sets `ZDOTDIR` to `~/.config/zsh`
(i.e. `${XDG_CONFIG_HOME}/zsh`), keeping Zsh dotfiles out of the home
directory root. The `.zshenv` must stay in `$HOME` so that Zsh can find it
before `ZDOTDIR` is set.

The `zdotdir` option lets you override the directory. Accepted forms:

| Value | Resolved to |
|---|---|
| `""` (default) | `~/.config/zsh` |
| `~/.something` | `<user_home>/.something` (expanded per user) |
| `$HOME/.something` | `<user_home>/.something` (expanded per user) |
| `/absolute/path` | `/absolute/path` (shared across all users) |

The resolved `ZDOTDIR` is injected into `~/.zshenv` between
`# >>> setup-shell-zdotdir >>>` / `# <<< setup-shell-zdotdir <<<` markers.

---

## Source chain

The following diagrams show the source chain for each shell invocation type.

**Bash login interactive** (e.g. `ssh`, `bash --login`):

```
/etc/profile
 └── /etc/shellenv (PATH, XDG, locale, umask)
 └── /etc/profile.d/*.sh
 └── /etc/bash.bashrc (if interactive)
      └── /etc/shellrc (GPG_TTY, dircolors, lesspipe, ...)
           └── /etc/shellaliases (ll, la, l)
~/.bash_profile
 └── ~/.shellenv (user PATH, XDG)
 └── ~/.bashrc
      ├── sources ~/.config/bash/bashtheme (downstream feature blocks)
      └── ~/.shellrc (user aliases/functions)
```

**Bash non-login interactive** (e.g. opening a new terminal tab):

```
/etc/bash.bashrc
 └── /etc/shellrc → /etc/shellaliases
 └── /etc/shellenv (via sentinel re-entry)
~/.bashrc
 ├── sources ~/.config/bash/bashtheme (downstream feature blocks)
 └── ~/.shellrc
```

**Bash non-interactive non-login** (e.g. `devcontainer exec`, VS Code tasks,
CI runners):

```
$BASH_ENV → /etc/bash/bashenv
 └── /etc/shellenv (PATH, XDG, locale, umask)
```

**Zsh login interactive** (e.g. `ssh`, default terminal):

```
/etc/zsh/zshenv → /etc/shellenv
~/.zshenv → ~/.shellenv + injects ZDOTDIR=~/.config/zsh
/etc/zsh/zprofile → /etc/profile → /etc/shellenv (sentinel skip) + profile.d
$ZDOTDIR/.zprofile → ~/.bash_profile → ~/.shellenv (sentinel skip)
/etc/zsh/zshrc → /etc/shellrc → /etc/shellaliases
$ZDOTDIR/.zshrc
 ├── sources $ZDOTDIR/zshtheme (downstream feature blocks)
 └── ~/.shellrc
$ZDOTDIR/.zlogin
```

**Zsh non-interactive** (e.g. `zsh -c "cmd"`, scripts with `#!/usr/bin/env zsh`):

```
/etc/zsh/zshenv → /etc/shellenv
~/.zshenv → ~/.shellenv + injects ZDOTDIR (not used in non-interactive)
```

---

## System path detection

The installer auto-detects the correct system configuration file paths for
each distribution. This is necessary because different Linux distributions
place bash and zsh config files in different locations.

### Bash system bashrc

The `shell__detect_bashrc` function probes these paths in order and returns
the first one that exists:

| Path | Distributions |
|---|---|
| `/etc/bash.bashrc` | Debian, Ubuntu, Arch, openSUSE |
| `/etc/bashrc` | Fedora, RHEL, CentOS |
| `/etc/bash/bashrc` | Gentoo, Alpine, Void |

### Bash bashenv

Placed next to the detected bashrc:

| Bashrc path | Bashenv path |
|---|---|
| `/etc/bash/bashrc` | `/etc/bash/bashenv` |
| `/etc/bash.bashrc` | `/etc/bashenv` |
| `/etc/bashrc` | `/etc/bashenv` |

### Zsh system directory

The `shell__detect_zshdir` function returns:

| Path | Distributions |
|---|---|
| `/etc/zsh/` | Debian, Ubuntu, Arch, Gentoo, Alpine, Void |
| `/etc/` | Fedora, RHEL, openSUSE, macOS |

---

## `BASH_ENV`

Non-interactive non-login Bash sessions (e.g. `devcontainer exec`,
`docker exec`, VS Code tasks, CI runners) do **not** read `/etc/profile`,
`/etc/bash.bashrc`, or any dotfiles. The only mechanism for injecting
environment variables into these sessions is the `BASH_ENV` variable.

The installer sets `BASH_ENV` in `/etc/environment`, which is read by PAM
(`pam_env`), systemd, and container runtimes. This causes non-interactive
Bash to source the `bashenv` file, which in turn sources `/etc/shellenv` to
provide `PATH`, `XDG_*`, locale, and other environment variables.

> **Note:** `BASH_ENV` is honored only by Bash, not by `sh`, `dash`, or Zsh.
> For non-interactive Zsh, the `/etc/zsh/zshenv` → `/etc/shellenv` chain
> provides equivalent coverage because Zsh always reads `zshenv`.

---

## `extend_path` helper

The `/etc/shellenv` file defines an `extend_path` function available in all
shells. It adds directories to `$PATH` without creating duplicates, silently
skips non-existent directories, and correctly handles paths with spaces.

```sh
# Prepend (inserted at front, preserving argument order):
extend_path --prepend "$HOME/.cargo/bin" "$HOME/.local/bin"

# Append (added at tail):
extend_path --append "/opt/myapp/bin"

# Both in one call:
extend_path --prepend "$HOME/bin" --append "/usr/games"
```

---

## System paths summary

| Path | Purpose |
|---|---|
| `/etc/shellenv` | Shared POSIX environment (PATH, XDG, locale, umask, `extend_path`) |
| `/etc/shellrc` | Shared interactive config (GPG_TTY, editor, dircolors, aliases) |
| `/etc/shellaliases` | Shared aliases (`ll`, `la`, `l`) |
| `/etc/profile` | Login shell profile for sh/bash |
| `/etc/bash.bashrc`\* | System-wide Bash interactive config |
| `/etc/bash/bashenv`\* | `BASH_ENV` target for non-interactive Bash |
| `/etc/environment` | `BASH_ENV` variable declaration |
| `/etc/zsh/zshenv`\* | System-wide Zsh environment (all invocations) |
| `/etc/zsh/zprofile`\* | System-wide Zsh login profile |
| `/etc/zsh/zshrc`\* | System-wide Zsh interactive config |
| `~/.config/zsh/` | `ZDOTDIR` — per-user Zsh config dir (`.zshrc`, `.zprofile`, `.zlogin`) |
| `~/.config/zsh/zshtheme` | Theme scaffold for downstream features (e.g. `install-ohmyzsh`) |
| `~/.config/bash/bashtheme` | Theme scaffold for downstream features (e.g. `install-ohmybash`) |

\* Exact path varies by distribution.

---

## File tree

```
files/
├── profile                    # → /etc/profile
│
├── shell/
│   ├── shellenv               # → /etc/shellenv
│   ├── shellrc                # → /etc/shellrc
│   └── shellaliases           # → /etc/shellaliases
│
├── bash/
│   ├── bashrc                 # → /etc/bash.bashrc (or equivalent)
│   └── bashenv                # → /etc/bash/bashenv (BASH_ENV target)
│
├── zsh/
│   ├── zshenv                 # → /etc/zsh/zshenv (or /etc/zshenv)
│   ├── zprofile               # → /etc/zsh/zprofile
│   └── zshrc                  # → /etc/zsh/zshrc
│
└── skel/
    ├── .shellenv              # → ~/
    ├── .shellrc               # → ~/
    ├── .bash_profile          # → ~/
    ├── .bashrc                # → ~/
    ├── .zshenv                # → ~/.zshenv  (always HOME; receives ZDOTDIR block)
    ├── .zprofile              # → $ZDOTDIR/
    ├── .zshrc                 # → $ZDOTDIR/
    └── .zlogin                # → $ZDOTDIR/
```
