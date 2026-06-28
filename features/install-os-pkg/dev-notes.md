# Developer Notes

> This section is an internal reference for contributors. It documents the
> design rationale, architectural decisions, and implementation details behind
> the YAML manifest format and Homebrew integration. It complements the
> user-facing sections above with the _why_ behind every design choice.

## Design rationale: why YAML

The original text DSL used custom section headers (`--- type [selectors]`)
and per-line selector syntax (`package [key=val]`). This worked for basic
cases but had fundamental limitations that motivated the move to YAML:

1. **No tooling support.** The custom syntax is unrecognizable by linters,
   formatters, language servers, and IDEs. Users get zero autocompletion,
   zero validation, and unhelpful error messages when the format is wrong.

2. **Flat structure.** Package-specific setup (keys, repos, scripts) had to
   live in separate sections scattered across the file. There was no way to
   co-locate all setup for a single third-party package (e.g. Docker CE
   needs a signing key + repo + package + post-install script — that was four
   separate sections in the text DSL).

3. **Homebrew complexity.** Brew introduces concepts (taps, casks, formulae,
   `--cask` flag) that don't map cleanly to the text DSL's `pkg`/`repo`/`key`
   section model. Taps are not repos (they're Git clones), casks are not
   regular packages, and brew has no signing keys.

4. **Extensibility ceiling.** Adding per-PM blocks (PPAs, COPR, modules,
   groups) to a line-oriented format would require increasingly complex
   header/selector syntax, creating a bespoke DSL that is harder to learn
   than a structured data format users already know.

YAML was chosen over other structured formats because:

- **`devfeats.sh` already has a proven YAML pipeline** — `yq` auto-download +
  YAML→JSON→`jq` processing. The same infrastructure is reused in
  `lib/ospkg.bash` via `_ospkg_ensure_yq()`.
- **JSON Schema provides machine-verifiable contracts** — one schema file
  serves as an authoritative specification, validation source, documentation
  generator, and IDE autocompletion backend. There is no ambiguity about
  what constitutes a valid manifest.
- **YAML is natively commentable** — unlike JSON, YAML supports line
  comments (`#`), which matters for manifests that users maintain by hand.
- **One file replaces many** — a single YAML manifest replaces the
  per-platform `.txt` files that features previously maintained in their
  `dependencies/` directories.

JSON manifests are equally valid (JSON is a strict subset of YAML), so
users who prefer JSON or generate manifests programmatically can use `.json`
files directly. The parser uses `yq`, which auto-detects the format — no
extension convention or explicit flag is required.

## Schema design

### Evaluated candidates

23+ schema structures were evaluated during the design phase. The major
categories were:

- **Flat package list** with per-entry PM overrides — every package becomes
  an object, making simple manifests unnecessarily verbose.
- **PM-first grouping** (`apt: {packages: [...]}`, `brew: {packages: [...]}`
  ) — clean for PM-specific packages but forces duplication for cross-
  platform packages. Cannot express "install `curl` on every platform"
  without repeating it in every PM block.
- **Separate `overrides` section** — moves PM name mappings to a dedicated
  top-level block, keeping `packages` clean but splitting logically related
  information across distant parts of the file.
- **Brewfile-inspired DSL** — Ruby-like entries (`brew "bat"`,
  `cask "iterm2"`) embedded in YAML strings — foreign syntax that defeats
  the purpose of using a structured format.
- **Conda `meta.yaml` style** — per-line comment selectors (`# [osx]`,
  `# [linux and x86_64]`) — clever but fragile, invisible to YAML parsers,
  and unvalidatable by JSON Schema.

### Selected: Schema #1 — Unified `packages` + PM-scoped blocks

Schema #1 was selected as the best balance of simplicity, expressiveness, and
cross-PM coverage:

- **`packages`** is the primary, PM-agnostic array. Most entries are bare
  strings that work on any platform. The 95% common case — a list of package
  names — is a simple YAML list with no objects, no nesting, and no
  boilerplate.
- **Package objects** add PM-specific name overrides inline, right where the
  package is defined. No indirection, no cross-referencing with a separate
  overrides section.
- **PM blocks** (top-level `apt:`, `brew:`, etc.) encapsulate inherently
  PM-specific operations that have no cross-platform equivalent (PPAs, taps,
  casks, COPR, modules). They are concise, scannable, and naturally
  exclusive — only the active PM's block runs.
- **Groups** allow shared `when`/`flags` without repeating conditions on
  every entry.

This layered design scales from minimal manifests (3 lines) to complex
cross-platform configurations (50+ lines) without syntactic overhead in
either case.

### Three refinements to the base schema

The base schema was refined with three additions based on real-world use case
analysis:

1. **`when` as dict OR list-of-dicts.** The original proposal only supported
   a single dict (AND of keys). Real-world manifests need OR across
   different key combinations — e.g. "install this package on (Ubuntu AND
   apt) OR (Fedora AND dnf)." The list-of-dicts form (`when: [{...}, {...}]`)
   provides this without adding a new keyword, a boolean expression parser,
   or a `not`/`or` operator.

2. **Group objects.** When many packages share the same condition or flags
   (e.g. `--no-install-recommends` for all apt packages), repeating the
   condition or flags on every entry is noisy and error-prone. Groups factor
   out shared properties. They also support nesting for hierarchical
   conditions (e.g. `kernel: linux` > `id_like: debian` > specific packages).

3. **Inline setup on packages/groups.** Third-party packages often need a
   signing key, a repository entry, and a post-install script. In the text
   DSL, these had to live in separate `--- key`, `--- repo`, and
   `--- script` sections scattered across the file. The inline `keys`/
   `repos`/`script`/`prescript` properties allow all setup for one logical
   package to live together. This improves readability and maintainability.
   The execution order is unchanged — inline items are collected and merged
   into the standard pipeline phases.

## Selector vocabulary comparison

Every package management ecosystem has its own conditional/selector
mechanism. The `when` clause was designed after studying all of them:

| System | Mechanism | Syntax | Scope |
|---|---|---|---|
| Homebrew Brewfile | Ruby conditionals | `if OS.mac?`, `unless ...` | Per-entry, arbitrary Ruby |
| conda `meta.yaml` | Jinja2 selectors | `# [osx]`, `# [linux and x86_64]` | Per-line comment suffix |
| rattler-build `recipe.yaml` | `if/then` YAML keys | `if: osx`, `then: ...` | Per-section |
| APT `sources.list` | `[arch=amd64]` | Square-bracket options | Per-repo line |
| Our text DSL (old) | `[key=val, key=val]` | Square-bracket blocks | Per-section or per-line |
| **YAML `when` clause** | **Dict / list-of-dicts** | **`when: { key: val }`** | **Per-entry, per-group** |

Design choices informed by this comparison:

- **Declarative over procedural.** Brewfile uses arbitrary Ruby; conda uses
  Jinja2. Both are powerful but require familiarity with the host language
  and are impossible to validate statically. `when` clauses are pure data —
  no language runtime needed, and they are fully validatable via JSON Schema.

- **Explicit key vocabulary.** Rather than free-form predicates, the `when`
  clause uses a fixed set of 6 keys (`pm`, `arch`, `kernel`, `id`,
  `id_like`, `version_id`) that map directly to detectable system facts.
  This avoids the ambiguity of conda's `osx` vs `unix` vs `linux` vs `win`
  (platform identifiers with overlapping semantics). The `version_codename`
  key from the old text DSL was deliberately dropped — codenames are
  Debian/Ubuntu-specific and not available on other distros.

- **AND/OR composability.** conda selectors use `and`/`or`/`not` keywords
  in comment strings. rattler-build uses boolean expressions. The
  dict/list-of-dicts approach provides equivalent composability with
  standard YAML syntax, no expression parser, and a clear mental model:
  _dict = AND, list = OR_.

- **No negation.** The `when` clause does not support `not`. Negation
  creates fragile manifests that break when new platforms are added (e.g.
  `not: { pm: apt }` silently includes every future PM). Positive assertions
  are explicit and forward-compatible. If negation becomes necessary in the
  future, it can be added as a `not` key inside a condition object without
  breaking the existing schema.

## `when` evaluation algorithm

The `when` clause is evaluated by `ospkg.bash` as follows:

1. **Absent `when`** → the entry always matches (unconditional).
2. **Single condition object** (dict) → evaluate as AND:
   - For each key in the object (e.g. `pm`, `arch`), compare its value(s)
     against the corresponding system fact.
   - If the value is a string → must match the system fact
     (case-insensitive string comparison).
   - If the value is an array → at least one element must match (OR within
     a key).
   - All keys in the object must match for the condition to pass (AND
     across keys).
3. **Array of condition objects** (list-of-dicts) → evaluate as OR:
   - Each element is evaluated as in step 2.
   - The entry matches if **any** element matches.
4. **Group stacking** → a group's `when` ANDs with each child's `when`:
   - A group with `when: A` containing a package with `when: B` requires
     both A AND B to match independently.
   - Nested groups stack: the effective condition is the AND of all ancestor
     `when` clauses plus the entry's own.
   - If any ancestor's `when` fails, the entire subtree is skipped — child
     conditions are not even evaluated.

## PM detection chain

The installer walks a fixed detection chain and selects the first PM binary
found in `PATH`. The chain order was chosen to match the relative prevalence
of distro families in containerised environments:

```
apt-get → apk → dnf → microdnf → yum → zypper → pacman → brew
```

`brew` is last because:

- On Linux, native PMs should always be preferred — they are faster, better
  integrated, and produce smaller container images than Linuxbrew.
- A Linux system with both `apt-get` and `brew` present is almost certainly
  a developer workstation where the user installed Linuxbrew on top of a
  Debian/Ubuntu base. Defaulting to the native PM is the right choice for
  99% of those cases. Set `prefer_linuxbrew: true` to opt in to the
  Linuxbrew-first behaviour.

On macOS, no native PM exists and `brew` is checked unconditionally (the
linear chain is not used). If `brew` is absent, the installer exits with an
actionable error rather than silently succeeding with nothing installed.

The `microdnf` entry exists because RHEL/UBI minimal images (`ubi8-minimal`,
`ubi9-minimal`) ship `microdnf` but not `dnf`. It is detected only when `dnf`
is absent, so standard RHEL images continue to use `dnf`.

## Brew root handling

Homebrew refuses to run as root on bare-metal systems to prevent accidental
damage to system files. However, it **explicitly allows root in containers**.

From brew's source code (`Library/Homebrew/brew.sh`,
`check-run-command-as-root()`):

```bash
check-run-command-as-root() {
  [[ "${EUID}" == 0 || "${UID}" == 0 ]] || return
  # Allow containers and CI:
  [[ -f /.dockerenv ]] && return
  [[ -f /run/.containerenv ]] && return
  [[ -f /proc/1/cgroup ]] && grep -E \
    "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup && return
  # Allow brew services (needs sudo):
  [[ "${HOMEBREW_COMMAND}" == "services" ]] && return
  # Allow read-only --prefix:
  [[ "${HOMEBREW_COMMAND}" == "--prefix" ]] && return
  odie "Running Homebrew as root is extremely dangerous..."
}
```

This is relevant because devcontainer features' `install.sh` **always runs
as root** (per the [devcontainer spec](https://containers.dev/implementors/features/)).
The installer leverages brew's own container detection to run `brew install`
directly as root inside containers — no user switching needed.

The devcontainer spec provides `_REMOTE_USER` and `_CONTAINER_USER`
environment variables at feature install time, but neither is needed for brew
operations. The brew prefix owner (obtained via `stat $(brew --prefix)`) is
the only identity that matters, and only on bare-metal systems where root
invocations must `su` to that owner.

## Brew user handling

The installer determines who should run `brew` commands based on three
factors: effective UID, container status, and brew prefix ownership.

| Context | EUID | Container? | Action |
|---|---|---|---|
| Devcontainer feature | 0 | Yes | Run brew directly (allowed by brew) |
| Standalone on bare metal | 0 (sudo) | No | `su` to owner of `$(brew --prefix)` |
| Normal user | ≠ 0 | — | Run brew directly |

This is handled internally by `ospkg.bash` — no user-facing `brew_user` option
is exposed. The rationale:

- **There is no ambiguity.** The brew prefix owner is deterministic. In
  containers, root is allowed. On bare metal with sudo, the prefix owner is
  the user who installed brew — obtainable via `stat`.
- **Exposing a `brew_user` option would be error-prone.** Users would need to
  know the brew prefix owner — information the installer can determine
  automatically.
- **Existing feature patterns vary unnecessarily.** `setup-shell` uses
  per-user config booleans (4 options); `install-miniforge` uses group
  permissions. Brew's single-user ownership model is simpler than both and
  doesn't warrant a user-facing option.

Container detection is implemented via `os__is_container()` in `lib/os.bash`,
reusing the same indicators brew checks: `/.dockerenv` (Docker),
`/run/.containerenv` (Podman), and cgroup inspection for `docker`,
`kubepods`, `garden`, `azpl_job`, `actions_job` (Kubernetes, Cloud Foundry,
Azure Pipelines, GitHub Actions).

## YAML parser infrastructure

The manifest parser uses a `yq` + `jq` pipeline:

1. **`yq`** (mikefarah/yq) reads the manifest and outputs it as JSON.
   `yq` auto-detects the input format — YAML and JSON are both accepted
   transparently. Since JSON is valid YAML, no explicit format detection is
   needed: the same code path handles both.
2. **`jq`** processes the JSON to extract packages, conditions, PM blocks,
   etc. into a normalized intermediate form consumable by bash.

`yq` is auto-downloaded if not present, using the same pattern as
`devfeats.sh`:

- Binary is fetched from [mikefarah/yq GitHub Releases](https://github.com/mikefarah/yq/releases)
  for the current platform (`linux`/`darwin`) and architecture
  (`amd64`/`arm64`).
- The download is checksum-verified (SHA-256) against the published checksums
  file.
- The binary is placed in a cache or temporary directory — no system
  installation, no `PATH` modification, no package manager dependency.

This is implemented via an `_ospkg_ensure_yq()` helper in `lib/ospkg.bash`
that is called once at the start of manifest parsing. The helper is idempotent
— if `yq` is already present (either system-installed or previously
downloaded), it is reused without re-downloading.

## Collected ordering

When inline keys, repos, and scripts from multiple packages and groups are
collected into their respective pipeline phases, they are merged in
**manifest declaration order** — the order in which items appear in the YAML
file.

Within each phase, the merge order is:

1. **PM block entries** (if present for the active PM).
2. **Top-level entries** (`prescripts`, `scripts`).
3. **Collected inline entries** from the `packages` array, in declaration
   order (depth-first traversal of nested groups).

This means:

- A PM block's keys are fetched before inline keys from packages.
- A PM block's scripts run before top-level `scripts`, which run before
  inline scripts.
- Within the `packages` array, items are processed in the order written.
  A key on package A (listed first) is fetched before a key on package B
  (listed second).

## Backward compatibility

The text DSL parser was removed entirely — a **clean break** with no
transition period, backward-compatibility layer, or automatic format
detection/migration.

Rationale:

- **The text DSL had no external users.** The feature had not had a stable
  release. The text DSL was never documented outside this repository and was
  never published to a package registry.
- **All in-repo manifests were migrated.** The feature-level
  `dependencies/base.yaml` files used by other features (which also consume
  `ospkg__run()`) were converted to YAML as part of the implementation.
- **A backward-compatible approach would have been costly.** Supporting two formats
  means maintaining two parsers, producing confusing error messages when the
  wrong format is used (or worse, silently misinterpreting one format as the
  other), and carrying documentation burden for a deprecated syntax
  indefinitely.
- **Clean breaks are cheaper at this stage.** Before a stable release, the
  cost of breaking changes is near zero. The JSON Schema provides a versioned
  contract that protects against future breakage.

## Cross-PM feature mapping

Not all PM concepts have equivalents across package managers. This table maps
manifest features to their PM-level implementations:

| Manifest concept | apt | apk | brew | dnf | yum | pacman | zypper |
|---|---|---|---|---|---|---|---|
| Regular packages | `apt-get install` | `apk add` | `brew install` | `dnf install` | `yum install` | `pacman -S` | `zypper install` |
| GUI apps (casks) | — | — | `brew install --cask` | — | — | — | — |
| Third-party repos | `sources.list.d/` | `/etc/apk/repositories` | `brew tap` | `yum.repos.d/` | `yum.repos.d/` | `pacman.conf` | `zypper addrepo` |
| PPAs | `add-apt-repository` | — | — | — | — | — | — |
| COPR | — | — | — | `dnf copr enable` | — | — | — |
| Module streams | — | — | — | `dnf module enable` | — | — | — |
| Package groups | — | — | — | `dnf groupinstall` | `yum groupinstall` | — | `zypper install -t pattern` |
| Signing keys | `gpg --dearmor` | — | — | `rpm --import` | `rpm --import` | `pacman-key` | `rpm --import` |
| Cache clean | `apt-get clean` | `apk cache clean` | `brew cleanup` | `dnf clean all` | `yum clean all` | `pacman -Scc` | `zypper clean` |
| List update | `apt-get update` | `apk update` | `brew update` | `dnf makecache` | `yum makecache` | `pacman -Sy` | `zypper refresh` |

Entries marked "—" indicate the concept does not exist or is not applicable
for that PM. Manifest entries targeting unsupported PM features are silently
skipped.
