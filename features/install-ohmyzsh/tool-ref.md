# Feature Reference

Oh My Zsh is a shell framework for Zsh that layers a standard startup model, bundled plugins/themes, and update tooling on top of a regular Zsh installation.[^omz-home][^omz-readme] It is not a replacement shell binary; it depends on Zsh and is loaded from shell startup files (typically `.zshrc`).[^omz-faq]

The project is distributed primarily as source code in a Git repository and is commonly installed by running the upstream `tools/install.sh` bootstrap script via `curl`, `wget`, or `fetch`.[^omz-readme][^omz-install] The same repository also ships first-party upgrade and uninstall scripts (`tools/upgrade.sh`, `tools/uninstall.sh`) plus template configuration files under `templates/`.[^omz-upgrade][^omz-uninstall][^omz-zshrc-template]

- **Homepage**: https://ohmyz.sh/[^omz-home]
- **Source Code**: https://github.com/ohmyzsh/ohmyzsh[^omz-repo]
- **Documentation**: https://github.com/ohmyzsh/ohmyzsh/wiki[^omz-wiki]
- **Latest Release**: Rolling `master` branch (no GitHub Releases or tags published, as of 2026-06-02).[^omz-releases][^omz-tags][^omz-branch]

## Tool Architecture

Oh My Zsh is a shell-script framework, not a compiled binary. It is loaded by sourcing `oh-my-zsh.sh` from the user shell initialization file (for example, `.zshrc`).[^omz-zshrc-template][^omz-readme]

At runtime, architecture is file/directory based:

- Core framework scripts live in the repository root and `lib/`.[^omz-repo]
- Built-in plugins are in `plugins/`, and built-in themes are in `themes/`.[^omz-repo][^omz-plugins-wiki][^omz-themes-wiki]
- User overrides/extensions are expected in `$ZSH/custom` (or an overridden `ZSH_CUSTOM`).[^omz-readme][^omz-faq]
- Updates are Git-based (`git pull` orchestrated by `tools/upgrade.sh`).[^omz-upgrade]

There is no client/server component, daemon, or external control plane. Execution context is the local interactive Zsh process. Oh My Zsh relies on:

- A working Zsh installation.[^omz-readme]
- A Git checkout for update workflows.[^omz-upgrade][^omz-faq]
- Shell startup files (`.zshrc`, optionally `.zprofile`) to activate it per user session.[^omz-readme][^omz-zshrc-template]

## Installation Methods

Upstream documents two practical installation paths:

- Bootstrap installer script (`tools/install.sh`) via network fetch.[^omz-readme][^omz-install]
- Manual Git clone + template setup.[^omz-readme]

### Installer Script (`tools/install.sh`)

#### Supported Platforms

- Linux, macOS, FreeBSD, Android, and WSL2 are documented as supported compatibility targets.[^omz-readme]
- Native Windows without a Unix-like environment is not supported for direct install.[^omz-faq]
- FAQ guidance for Windows specifically points to Windows 10 (2004+) or Windows 11 with either Cygwin or WSL for Zsh-based usage.[^omz-faq]

#### Dependencies

##### Common Dependencies

- `zsh` (upstream notes 4.3.9+ works; 5.0.8+ preferred).[^omz-readme]
- `git` (upstream recommends 2.4.11+).[^omz-readme]
- A downloader for bootstrap invocation (`curl`, `wget`, or `fetch`).[^omz-readme][^omz-install]

##### Platform-Specific Dependencies

- If default shell switching is enabled (`CHSH=yes`), `chsh` must exist and a valid `zsh` path must be accepted by shell configuration (for example `/etc/shells` checks in installer logic on non-Termux systems).[^omz-install]
- On Termux, installer logic short-circuits `sudo`/`chsh` shell-switch behavior and uses `zsh` directly for shell targeting.[^omz-install]
- Cygwin users must use Cygwin Git; installer rejects Windows/MSYS Git in Cygwin context.[^omz-install]

#### Installation Steps

1. Ensure prerequisites (`zsh`, `git`, downloader) are installed.[^omz-readme]
2. Run one of the official bootstrap commands, for example:
   - `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`
   - `sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`
   - `sh -c "$(fetch -o - https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`[^omz-readme]
3. If `raw.githubusercontent.com` is blocked, use the mirrored endpoint `https://install.ohmyz.sh` with the same pattern.[^omz-readme][^omz-faq]
4. Installer clones the repository (shallow fetch), writes/updates `.zshrc` from template, optionally prompts for default-shell change, then can execute `zsh -l` unless disabled.[^omz-install]

#### Installation Verification

Recommended verification after script completion:

- Confirm installation directory exists (default: `$HOME/.oh-my-zsh`, unless `ZSH`/`ZDOTDIR` changed).[^omz-install]
- Confirm startup file contains:
  - `export ZSH="..."`
  - `source $ZSH/oh-my-zsh.sh`[^omz-zshrc-template][^omz-install]
- Start a new Zsh login shell and verify the prompt/theme/plugins load (`exec zsh -l` or open a new terminal).[^omz-install][^omz-readme]

#### Configuration Options

##### Version Selection

Installer supports source selection through environment variables:

- `REPO` (`owner/repository` format).
- `REMOTE` (full Git URL; takes precedence over `REPO`).
- `BRANCH` (checkout target branch, default `master`).[^omz-install][^omz-readme]

Notes:

- Upstream has no published release/tag stream; installs are effectively branch-based unless you post-process with Git checkout operations.[^omz-releases][^omz-tags]

##### Installation Path

- Default install path is `$HOME/.oh-my-zsh`.[^omz-readme][^omz-install]
- `ZSH` overrides installation root.[^omz-readme][^omz-install]
- `ZDOTDIR` changes dotfile root and influences default `ZSH` derivation (`$ZDOTDIR/ohmyzsh` when set and different from `$HOME`).[^omz-install]

##### User Targeting

- Installer is user-scoped by default (`$HOME`, user `.zshrc`).[^omz-install]
- Global/system-wide usage is documented separately in FAQ and requires manual multi-user layout decisions (`/usr/share/ohmyzsh` or `/opt/ohmyzsh`, per-user `.zshrc` references).[^omz-faq]
- For global layouts, FAQ caveats are important:
  - Automatic updates are effectively skipped when global install is not writable by the user or not managed as a writable git checkout.
  - If global `$ZSH/cache` is not writable, cache use shifts to `$HOME/.cache/oh-my-zsh`.
  - `ZSH_CUSTOM` remains `$ZSH/custom` unless explicitly overridden per user.
  - Manual root-side update can be run as `zsh /path/to/ohmyzsh/tools/upgrade.sh`.[^omz-faq]

##### Required Privileges

- Typical per-user installs do not require root.
- If shell-changing is enabled and policy requires elevation, installer may invoke `sudo chsh` when possible.[^omz-install]
- Upstream recommends avoiding root-user Oh My Zsh setup for safety/recovery reasons.[^omz-faq]

##### Tool-Specific Configurations

Installer environment variables/options:

- Path/repository controls:
  - `ZDOTDIR`
  - `ZSH`
  - `REPO`
  - `REMOTE`
  - `BRANCH`[^omz-install]
- Behavior controls:
  - `CHSH` (`no` to skip changing default shell)
  - `RUNZSH` (`no` to avoid launching zsh at end)
  - `KEEP_ZSHRC` (`yes` to avoid replacing existing `.zshrc`)
  - `OVERWRITE_CONFIRMATION` (`no` to skip overwrite prompt)[^omz-install]
- CLI flags:
  - `--skip-chsh`
  - `--unattended` (sets `CHSH=no`, `RUNZSH=no`, and disables overwrite confirmation in non-interactive flow)
  - `--keep-zshrc`[^omz-install][^omz-readme]

Additional official runtime configuration knobs (template + README docs):

- Theme selection and random-theme controls: `ZSH_THEME`, `ZSH_THEME_RANDOM_CANDIDATES`, `ZSH_THEME_RANDOM_IGNORED`.[^omz-zshrc-template][^omz-readme]
- Completion behavior toggles: `CASE_SENSITIVE`, `HYPHEN_INSENSITIVE`, `COMPLETION_WAITING_DOTS`.[^omz-zshrc-template]
- Shell UX toggles: `DISABLE_MAGIC_FUNCTIONS`, `DISABLE_LS_COLORS`, `DISABLE_AUTO_TITLE`, `ENABLE_CORRECTION`, `DISABLE_UNTRACKED_FILES_DIRTY`, `HIST_STAMPS`.[^omz-zshrc-template]
- Update checks: `zstyle ':omz:update' mode|frequency|verbose ...` before loading Oh My Zsh.[^omz-readme][^omz-zshrc-template]
- Custom content path override: `ZSH_CUSTOM=/path/to/custom`.[^omz-zshrc-template]
- Alias loading controls via zstyle scopes (`:omz:*`, `:omz:lib:*`, `:omz:plugins:*`, etc.).[^omz-readme]
- Async git prompt controls via `zstyle ':omz:alpha:lib:git' async-prompt no|force`.[^omz-readme]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- No special binary `PATH` bootstrap is required for core framework loading.
- Users may need to re-add PATH customizations from prior shell configs after replacing `.zshrc`.[^omz-readme][^omz-faq]

##### Configuration Files

Installer may create/modify:

- `~/.zshrc` (from template, with `export ZSH=...`).[^omz-install][^omz-zshrc-template]
- `~/.zshrc.pre-oh-my-zsh` backup (and timestamped rollover backups of earlier backups).[^omz-install][^omz-faq]
- `~/.shell.pre-oh-my-zsh` when changing default shell, used later by uninstaller.[^omz-install][^omz-uninstall]

##### Environment Variables

Important persistent variables in config:

- `ZSH` (framework path).
- `ZSH_THEME`.
- Optional update settings via `zstyle ':omz:update' ...` modes/frequency/verbosity.[^omz-zshrc-template][^omz-readme]

##### Activation Scripts

- Activation occurs through `source $ZSH/oh-my-zsh.sh` in `.zshrc`.[^omz-zshrc-template]
- Installer can launch a new login shell (`exec zsh -l`) unless disabled.[^omz-install]

##### Cleanup

- Installer itself does not perform package-manager cleanup.
- It creates temporary write `~/.zshrc-omztemp` then moves it atomically to `.zshrc`.[^omz-install]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Standard interactive update command: `omz update`.[^omz-readme][^omz-faq]
- Scripted update path: `$ZSH/tools/upgrade.sh` (supports `-i` and `-v default|minimal|silent`).[^omz-readme][^omz-faq][^omz-upgrade]
- Upgrade requires Git repository state and write access to install directory.[^omz-faq]
- Install script uses shallow clone (`--depth=1`); if commit-level checkout is required later, unshallow first (`git fetch --unshallow`).[^omz-install][^omz-faq]

##### Uninstallation

- First-party command: `uninstall_oh_my_zsh`.[^omz-readme][^omz-faq]
- Uninstaller behavior includes:
  - Attempt shell restore from `~/.shell.pre-oh-my-zsh` via `chsh`.
  - Remove `~/.oh-my-zsh`.
  - Rename current `.zshrc` to timestamped `.zshrc.omz-uninstalled-...`.
  - Restore `.zshrc.pre-oh-my-zsh` if present.[^omz-uninstall][^omz-faq]
- First-party `tools/uninstall.sh` is default-path-oriented (`~/.oh-my-zsh`, `~/.zshrc`) and does not automatically honor custom `ZSH` or `ZDOTDIR` layouts; custom-path installs need manual cleanup of the real install root and dotfiles.[^omz-uninstall][^omz-install]
- Manual fallback is possible: `rm -rf $ZSH`, edit shell config, and switch shell explicitly.[^omz-faq]

##### Idempotency

- Installer is intentionally not in-place idempotent over an existing `$ZSH` directory; it exits and asks user to remove/repoint path.[^omz-install]
- `.zshrc` handling is protective (backup first, optional keep behavior, explicit overwrite confirmation unless disabled).[^omz-install][^omz-faq]

#### Notes and Best Practices

- Prefer non-root per-user install unless there is a clear multi-user requirement.[^omz-faq]
- Use `--unattended` for automation and CI/container scenarios.[^omz-readme][^omz-install]
- In restricted networks, prefer `https://install.ohmyz.sh` mirror.[^omz-readme][^omz-faq]

### Manual Git Clone Installation

#### Supported Platforms

- Same compatibility matrix as project overall: Linux/macOS/FreeBSD/Android/WSL2 (no native non-WSL Windows path).[^omz-readme][^omz-faq]

#### Dependencies

##### Common Dependencies

- `zsh`.
- `git`.[^omz-readme]

##### Platform-Specific Dependencies

- `chsh` if changing login shell from non-Zsh to Zsh.[^omz-readme]

#### Installation Steps

1. Clone repository to desired location (default example `~/.oh-my-zsh`).[^omz-readme]
2. Optionally back up existing `.zshrc` (`cp ~/.zshrc ~/.zshrc.orig`).[^omz-readme]
3. Copy template config to `~/.zshrc` (`cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc`).[^omz-readme]
4. Optionally change default shell (`chsh -s $(which zsh)`).[^omz-readme]
5. Open a new terminal/login shell to activate configuration.[^omz-readme]

#### Installation Verification

- Verify clone directory exists and contains expected subdirectories (`plugins`, `themes`, `tools`).[^omz-repo]
- Verify `.zshrc` sources `oh-my-zsh.sh` and references the intended `ZSH` path.[^omz-zshrc-template]
- Open new shell and verify prompt/theme loading.[^omz-readme]

#### Configuration Options

##### Version Selection

- Full Git checkout flow is available in manual mode (`git checkout` to branch/commit after clone).
- Installer-only env vars (`REPO`, `REMOTE`, `BRANCH`) are not needed because repository source is selected directly at clone time.[^omz-readme][^omz-install]

##### Installation Path

- Any path can be used as long as `.zshrc` exports matching `ZSH` and sources `oh-my-zsh.sh` from that path.[^omz-readme][^omz-zshrc-template]

##### User Targeting

- By default this is per-user and local to that user home.
- For global deployments, FAQ recommends globally readable root-owned location and per-user `.zshrc` references.[^omz-faq]

##### Required Privileges

- Per-user clone typically requires no elevated privileges.
- System-wide clone path (`/usr/share/ohmyzsh`, `/opt/ohmyzsh`) requires elevated privileges and additional per-user setup.[^omz-faq]

##### Tool-Specific Configurations

- Configure theme/plugins/settings directly in `.zshrc` (for example `ZSH_THEME`, `plugins=(...)`, `zstyle ':omz:update' ...`).[^omz-zshrc-template][^omz-readme]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- No mandatory PATH export for framework itself.
- Reapply custom PATH additions from prior shell config if commands disappear after migration.[^omz-readme][^omz-faq]

##### Configuration Files

- Main file: `.zshrc`.
- Optional backup file in manual flow: `.zshrc.orig` (or your chosen backup scheme).[^omz-readme]

##### Environment Variables

- `ZSH`, `ZSH_THEME`, optional update zstyles and custom folder controls (`ZSH_CUSTOM`) in `.zshrc`.[^omz-zshrc-template][^omz-readme]

##### Activation Scripts

- `source $ZSH/oh-my-zsh.sh` in `.zshrc`.[^omz-zshrc-template]

##### Cleanup

- Manual cleanup is user-managed (`rm -rf` clone dir and config edits as needed).[^omz-faq]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Use standard update paths (`omz update`, `$ZSH/tools/upgrade.sh`) if clone is still a normal Git repo.[^omz-readme][^omz-upgrade]
- Manual checkout allows switching branches/commits directly.

##### Uninstallation

- Use `uninstall_oh_my_zsh` or perform manual removal and shell/config restoration.[^omz-readme][^omz-uninstall][^omz-faq]

##### Idempotency

- Manual steps are operator-driven; behavior depends on whether target directory/files already exist.
- Protecting existing `.zshrc` is explicit in docs as an optional pre-step.[^omz-readme]

#### Notes and Best Practices

- Manual method is preferred when explicit review/control of repository state is required.[^omz-readme]
- For multi-user systems, follow FAQ global install constraints (permissions, update handling, cache/custom path implications).[^omz-faq]

## Dev Container Setup

Practical container-oriented guidance:

- Use unattended/non-interactive installer behavior to avoid shell-change prompts and automatic shell re-exec in image build phases (`--unattended` or equivalent env settings).[^omz-readme][^omz-install]
- Ensure installation targets the intended non-root home when features are installed as root during build.[^devcontainers-common-utils-main]
- If default-shell mutation is desired in containers, apply it explicitly and carefully (for example `chsh` handling differs by distro; Alpine may need PAM adjustment, as seen in common-utils implementation).[^devcontainers-common-utils-main]

Comparative implementations in established feature repos:

- `devcontainers/features` `common-utils`:
  - Exposes options `installOhMyZsh`, `installOhMyZshConfig`, `configureZshAsDefaultShell`.
  - Performs shallow clone with git safety configs.
  - Seeds `.zshrc` from template and appends `zstyle ':omz:update' mode disabled` for predictable container behavior.[^devcontainers-common-utils-feature][^devcontainers-common-utils-main]
- `devcontainers-extra/features` `zsh-plugins`:
  - Ensures Oh My Zsh exists (invokes upstream installer if missing).
  - Installs custom plugins via shallow `git clone` into `$HOME/.oh-my-zsh/custom/plugins`.
  - Mutates `plugins=(...)` in `.zshrc` from feature options.[^devcontainers-extra-zsh-install][^devcontainers-extra-zsh-feature][^devcontainers-extra-zsh-readme]

## Plugins and Extensions

Oh My Zsh plugin/theme model is script-centric and local-file based.

Built-in capabilities:

- Hundreds of bundled plugins and 150+ bundled themes are provided by the main repository.[^omz-home][^omz-readme]
- Plugin catalog/documentation is maintained in wiki and plugin directories.[^omz-plugins-wiki][^omz-repo]
- Theme catalog is maintained in wiki and `themes/` directory.[^omz-themes-wiki][^omz-repo]

How to enable/configure:

- Set `plugins=(...)` in `.zshrc`; items are whitespace-separated (no commas).[^omz-readme][^omz-plugins-wiki]
- Set `ZSH_THEME="..."` in `.zshrc`; `random` and candidate/ignore lists are supported.[^omz-readme][^omz-zshrc-template]

Custom and external extensions:

- Add custom plugins under `$ZSH/custom/plugins/` and enable by name in `plugins=(...)`.[^omz-readme]
- A custom plugin with the same name as a built-in plugin overrides the built-in one.[^omz-readme]
- External plugin/theme indexes are available in wiki (`External plugins`, `External themes`).[^omz-faq]

Operational cautions:

- Some theme prompts require Powerline/Nerd fonts in the terminal emulator.[^omz-readme][^omz-faq]
- Plugin manager integrations may require explicit `ZSH_CACHE_DIR`/`fpath` handling for dynamic completions, as documented in FAQ.[^omz-faq]

## References

[^omz-home]: [Oh My Zsh Homepage](https://ohmyz.sh/) - Official project site and high-level positioning.
[^omz-repo]: [ohmyzsh/ohmyzsh repository](https://github.com/ohmyzsh/ohmyzsh) - Canonical source tree and project structure.
[^omz-readme]: [README.md (pinned commit `70ad5e3`)](https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/70ad5e3df8f7bed68aa6672029496926e632aedd/README.md) - Official installation, prerequisites, updates, plugins/themes usage.
[^omz-wiki]: [Oh My Zsh Wiki Home](https://github.com/ohmyzsh/ohmyzsh/wiki/Home) - Official documentation hub.
[^omz-install]: [tools/install.sh (pinned commit `70ad5e3`)](https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/70ad5e3df8f7bed68aa6672029496926e632aedd/tools/install.sh) - Authoritative installer behavior, env vars, and idempotency logic.
[^omz-upgrade]: [tools/upgrade.sh (pinned commit `70ad5e3`)](https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/70ad5e3df8f7bed68aa6672029496926e632aedd/tools/upgrade.sh) - Update mechanics and script flags.
[^omz-uninstall]: [tools/uninstall.sh (pinned commit `70ad5e3`)](https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/70ad5e3df8f7bed68aa6672029496926e632aedd/tools/uninstall.sh) - Uninstall sequence and shell/config restoration behavior.
[^omz-zshrc-template]: [templates/zshrc.zsh-template (pinned commit `70ad5e3`)](https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/70ad5e3df8f7bed68aa6672029496926e632aedd/templates/zshrc.zsh-template) - Default runtime configuration shape and key variables.
[^omz-faq]: [FAQ Wiki](https://github.com/ohmyzsh/ohmyzsh/wiki/FAQ) - Global install guidance, uninstall semantics, update caveats, and operational best practices.
[^omz-plugins-wiki]: [Plugins Wiki](https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins) - Plugin catalog and plugin activation guidance.
[^omz-themes-wiki]: [Themes Wiki](https://github.com/ohmyzsh/ohmyzsh/wiki/Themes) - Theme catalog and theme requirements.
[^omz-releases]: [Releases page](https://github.com/ohmyzsh/ohmyzsh/releases/latest) - Indicates no published releases.
[^omz-tags]: [Tags API (latest page)](https://api.github.com/repos/ohmyzsh/ohmyzsh/tags?per_page=1) - Returns empty list at time of verification.
[^omz-branch]: [Master branch API](https://api.github.com/repos/ohmyzsh/ohmyzsh/branches/master) - Confirms active rolling branch reference.
[^devcontainers-common-utils-main]: [devcontainers/features `src/common-utils/main.sh` (pinned commit `72df8a5`)](https://raw.githubusercontent.com/devcontainers/features/72df8a5f191f840a66dc2e2ced10a136e4d75173/src/common-utils/main.sh) - Real-world devcontainer integration logic for Zsh/Oh My Zsh.
[^devcontainers-common-utils-feature]: [devcontainers/features `src/common-utils/devcontainer-feature.json` (pinned commit `72df8a5`)](https://raw.githubusercontent.com/devcontainers/features/72df8a5f191f840a66dc2e2ced10a136e4d75173/src/common-utils/devcontainer-feature.json) - Option surface for container setup.
[^devcontainers-extra-zsh-install]: [devcontainers-extra/features `src/zsh-plugins/install.sh` (pinned commit `1ab95b2`)](https://raw.githubusercontent.com/devcontainers-extra/features/1ab95b2db0c1cba87a97bcd532fa42c6a8a6d320/src/zsh-plugins/install.sh) - Comparative plugin-install strategy on top of Oh My Zsh.
[^devcontainers-extra-zsh-feature]: [devcontainers-extra/features `src/zsh-plugins/devcontainer-feature.json` (pinned commit `1ab95b2`)](https://raw.githubusercontent.com/devcontainers-extra/features/1ab95b2db0c1cba87a97bcd532fa42c6a8a6d320/src/zsh-plugins/devcontainer-feature.json) - Exposed options for plugin feature.
[^devcontainers-extra-zsh-readme]: [devcontainers-extra/features `src/zsh-plugins/README.md` (pinned commit `1ab95b2`)](https://raw.githubusercontent.com/devcontainers-extra/features/1ab95b2db0c1cba87a97bcd532fa42c6a8a6d320/src/zsh-plugins/README.md) - User-facing behavior and option documentation.
