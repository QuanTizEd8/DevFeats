# Unified condition context

DevFeats features evaluate platform and install constraints through a single **context registry** (`_CTX__REGISTRY`) with three namespaces. All when-matching and URI/manifest pattern expansion reads from this registry.

| Namespace | Contents | Populated by |
|-----------|----------|--------------|
| `os.*` | `/etc/os-release` fields (Linux) or macOS `sw_vers` mapping | `_ctx__ensure_registry` → `_ctx__load_linux_os` / `_ctx__load_darwin_os` |
| `plat.*` | Kernel, arch tokens, PM key, libc, rust triple, … | `os.sh` helpers + `ospkg__pm_key` / `ospkg__deb_arch` in `_ctx__ensure_registry` |
| `feat.*` | Install options (`version`, `tag`, `method`, `prefix`, …) | install template `__ctx_sync_*` helpers |

Implementation: [`lib/ctx.sh`](../../../../lib/ctx.sh), [`lib/ctx-match.jq`](../../../../lib/ctx-match.jq).

## Registry keys

### `os.*` (from os-release / macOS)

| Key | Source |
|-----|--------|
| `os.id` | `ID=` (Linux) or `macos` |
| `os.id_like` | `ID_LIKE=` (token list) |
| `os.name`, `os.version`, `os.version_id`, `os.version_codename`, … | os-release fields |
| `os.version_id_major` | Derived from `version_id` (component before first `.`) |
| `os.version_id_mm` | Derived major.minor prefix |

### `plat.*` (computed platform)

| Key | Meaning |
|-----|---------|
| `plat.kernel` | `uname -s` (`Linux`, `Darwin`) |
| `plat.kernel_gh`, `plat.kernel_macos`, `plat.kernel_osx` | Release naming variants |
| `plat.machine` | Raw `uname -m` |
| `plat.machine_release` | Normalized release arch (`amd64`, `arm64`, …) |
| `plat.machine_gh`, `plat.machine_node`, `plat.machine_bitness` | Release naming variants |
| `plat.platform` | Distro family (`debian`, `alpine`, `macos`, …) |
| `plat.rust_triple`, `plat.libc` | Target triple and libc family |
| `plat.pm` | Package manager **key** (`apt`, not `apt-get`) |
| `plat.deb_arch` | Debian architecture when `plat.pm=apt` |

### `feat.*` (install lifecycle)

| Key | Global source | When set |
|-----|---------------|----------|
| `feat.version_input` | `VERSION_INPUT` (or `VERSION` before capture) | `__ctx_sync_version__` |
| `feat.version` | `VERSION` | `__ctx_sync_version__` |
| `feat.tag` | `_FEAT_RESOLVED_TAG` | `__ctx_sync_version__` |
| `feat.method` | `METHOD` | `__ctx_sync_method__` |
| `feat.prefix` | `_RESOLVED_PREFIX` | `__ctx_sync_prefix__` |

Sync helpers (in [`features/install.tmpl.bash`](../../../../features/install.tmpl.bash)):

- `__ctx_sync_version__` — mirror version globals
- `__ctx_sync_method__` — mirror `METHOD`
- `__ctx_sync_prefix__` — mirror `_RESOLVED_PREFIX`
- `__ctx_sync__` — all three (called at end of `__init_args__`)

Feature hooks that mutate `VERSION`, `METHOD`, etc. must call the appropriate `__ctx_sync_*` (or `ctx__set`) immediately after.

## When blocks (metadata)

When constraints are **YAML** emitted at build time and evaluated by `ctx__match_when` / `ctx-match.jq`:

```yaml
when:
  plat.kernel: linux
  plat.machine_release: amd64

# OR groups
when:
  - plat.pm: apt
  - plat.pm: apk

# Operator dicts (AND within key)
when:
  feat.version:
    gte: "1.0"
    lt: "2.0"
```

Rules:

- Keys must be **qualified**: `os.id`, `plat.pm`, `feat.version` — legacy flat keys (`arch`, `semver_lte`) are rejected by schema and `when_util`.
- **No case flavors** in when YAML (`plat.kernel:lower` is invalid). Flavors are pattern-expand-only.
- Ordering operators (`gte`, `lt`, …) accept strings only (not arrays).

## Pattern expansion

URI, manifest, and option strings use `{namespace.key}` tokens expanded by `ctx__expand_pattern`:

```text
https://github.com/org/repo/releases/download/{feat.tag}/app-{plat.machine_release}.tar.gz
{feat.version>=1.7?new:old}
{plat.kernel:lower}
{plat.deb_arch:lower}
{plat.kernel==linux?{plat.libc==musl?-musl:}:}
```

Case flavors (`:upper`, `:lower`, `:title`) apply **only** in pattern tokens, not in when YAML.

Unknown keys in conditionals take the false branch; unknown bare tokens are emitted unchanged.

## Migration from legacy tokens

| Legacy when key | Qualified key |
|-----------------|---------------|
| `id:` | `os.id:` |
| `arch:` | `plat.machine_release:` |
| `kernel:` | `plat.kernel:` |
| `pm:` | `plat.pm:` |
| `semver_lte:` | `feat.version: {lte: …}` |

| Legacy pattern token | Replacement |
|---------------------|-------------|
| `{VERSION}` | `{feat.version}` |
| `{VERSION_INPUT}` | `{feat.version_input}` |
| `{TAG}` | `{feat.tag}` |
| `{METHOD}` | `{feat.method}` |
| `{PREFIX}` | `{feat.prefix}` |
| `{OS}` | `{plat.kernel:lower}` |
| `{KERNEL}` | `{plat.kernel}` |
| `{ARCH}` | `{plat.machine_release}` |
| `{OS_ARCH}` | `{plat.machine}` |
| `{OS_ID}` | `{os.id}` |
| `{PLATFORM}` | `{plat.platform}` |
| `{RUST_TRIPLE}` | `{plat.rust_triple}` |
| `{LIBC}` | `{plat.libc}` |
| `{OS==linux?…}` | `{plat.kernel==linux?…}` |

Run `.dev/lib/proman/migrate_ctx_metadata.py` to codemod metadata files.

## `os.id_like` authoring

`os.id_like` is a **whitespace-separated token list**, not a single string. Matching uses token membership:

- `eq: rhel` matches `ID_LIKE="rhel centos fedora"`
- `eq: "rhel centos fedora"` as one scalar does **not** match (single token only)
- Ordering operators on `os.id_like` always fail (fail-closed)

## API summary

| Function | Role |
|----------|------|
| `ctx__set key=value …` | Write registry (sole write API) |
| `ctx__get key` | Read value; triggers `_ctx__ensure_registry` |
| `ctx__json` | Flat JSON object for jq evaluators |
| `ctx__pairs` | Iterate `key=value` lines |
| `ctx__expand_pattern` | Expand `{qualified.key}` and conditionals |
| `ctx__match_when` / `ctx__match_spec` | Evaluate YAML when via `ctx-match.jq` |
| `ctx__compare` | Bash-side comparison (used by pattern conditionals) |
