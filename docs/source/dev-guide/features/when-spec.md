# WhenSpec reference

Unified condition blocks (`when`) appear in method feasibility checks, prefix
`platform_overrides`, ospkg dependency manifests, and optional `binary_src`
entries. All routes share one wire format and two runtimes.

## Wire format

Serialization is produced by `serialize_when()` in the build pipeline:

| YAML shape | Wire string |
|------------|-------------|
| Object (AND) | `key=val key2=val2` |
| Array of objects (OR) | newline-separated AND groups |
| Value arrays | `key=a\|b\|c` (OR within one key) |

Example:

```yaml
when:
  - {kernel: linux, arch: [amd64, arm64], semver_lte: "12.1.2"}
  - {kernel: darwin, arch: amd64, semver_lte: "12.1.2"}
```

→

```
kernel=linux arch=amd64|arm64 semver_lte=12.1.2
kernel=darwin arch=amd64 semver_lte=12.1.2
```

## Key namespaces

| Namespace | Keys | Resolution |
|-----------|------|------------|
| Platform | `kernel`, `arch`, `pm`, `id`, `id_like`, `version_id`, … | `ospkg__os_release_match` (case-insensitive) |
| Semver | `semver_lte`, `semver_lt`, `semver_gte`, `semver_gt`, `semver` | Compare against `VERSION` from feature context |
| Feature ctx | `VERSION`, `TAG`, `METHOD`, `VERSION_INPUT` | Explicit context pairs from `__feat_context_pairs__()` |

Do **not** use `version_*` keys — they collide with `/etc/os-release` `VERSION`.

## Runtimes

### Bash — `lib/ctx.bash`

- `ctx__match_when` — any group matches (OR)
- `ctx__select_first` — first matching group wins
- `ctx__match_spec` — AND over atoms

Template boundary helpers:

- `__feat_context_pairs__()` — supplies feat vars to lib code
- `__feat_match_when__()` — method auto-resolution (quiet)
- `__feat_filter_binary_src__()` — filters `BINARY_SRC` option lines

For platform-only checks (no feat context), call `ctx__match_when` / `ctx__match_spec`
directly with no `--` context pairs.

### jq — `lib/ospkg-manifest.jq`

`when_matches` / `cond_matches` evaluate the same keys against merged `$ctx`
(OS release fields + `--extra-var` feat context from `__dep_ospkg_extra_args__`).

## Pattern substitution vs conditions

Plain tokens (`{KERNEL}`, `{OS}`) use `_OS__RELEASE_VARS` output spelling
(`Linux`/`Darwin` vs `linux`/`darwin`). **Conditionals** in patterns
(`{KERNEL==linux?…}`) use `cond__eval_atom` and match case-insensitively via
ospkg — same semantics as when blocks.

## Selection semantics

| Use case | Semantics |
|----------|-----------|
| Method `when`, ospkg manifest `when`, sys_req guards | Any matching group (OR) |
| Prefix `platform_overrides` | First matching group (via `users__first_writeable_path`) |
| `binary_src` TAB-when lines | Per-line filter (AND atoms within line) |

## binary_src wire format

Each `binary_src` option line is either:

- `path` — unconditional
- `path<TAB>when-atoms` — install archive member only when atoms match

Metadata object form `{path: …, when: …}` serializes to the TAB form in the
option default via `serialize_binary_src()`.
