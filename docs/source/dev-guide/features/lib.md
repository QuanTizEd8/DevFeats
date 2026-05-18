# Shared Library

The `lib/` directory contains reusable modules (mostly bash) that are sourced by `install.bash` installer scripts. Each module is a file containing related functions that abstract common operations for a specific domain, e.g. OS package installation, GitHub API calls, checksum verification, user management, and shell configuration. During builds, `lib/` is copied into every feature's `src/*/_lib/`, so that `install.bash` can source each module as `$_BASE_DIR/_lib/<module-name>.sh`.

> **Always check here before implementing something from scratch.** If a function does what you need, use it. If you are writing logic that could benefit other features, add it to `lib/` instead of keeping it inline.

## Guard Pattern

To prevent double-sourcing and circular imports, all shell modules must start with an idempotency guard:

```bash
[[ -n "${_MODULE_NAME__LIB_LOADED-}" ]] && return 0
_MODULE_NAME__LIB_LOADED=1
```

Every public function is covered by the bats unit suite under `test/lib/`. Run `just test-lib` to verify changes locally before pushing.

**Multi-value conventions:** many helpers return multiple logical items as one stdout line per item (empty list → no output). This composes naturally with pipes, `while read -r`, and `mapfile`.

## Documentation

Each `lib/*.sh` module is automatically parsed and rendered into an API reference page under `docs/source/library/<module-name>.md`. The generator reads structured comments — no external tools required. This section explains what to write so that the output renders correctly.

### Module header

The first comment block immediately after the shebang becomes the module's page header. The **first non-empty line** is the one-line summary (used in the library index card); everything after the first blank comment line is the long description.

```bash
#!/usr/bin/env bash
# One-line summary of the module.
#
# Longer description. May span multiple lines and contain
# light Markdown formatting.
```

Both the summary and the long description are optional. A module without a summary still gets its own API reference page (all `@brief` function annotations are rendered), but it is omitted from the library index and a warning is printed to stderr.

### Function annotations

All functions — public and private — should use the `# @brief` format. The generator filters out private functions (names starting with `_`) by default; pass `--include-private` to the `gen-docs-data` CLI to include them.

**`@brief` line format:**

```
# @brief <signature> — <one-line description>.
```

- `<signature>` is the full call signature: function name followed by any positional arguments, flags, or metavariables (e.g. `json__root_scalar_stdin <key>` or `logging__info <line>...`).
- The separator between signature and description must be an em-dash (`—`, U+2014). A space-hyphen-space (` - `) is also accepted but the em-dash is preferred.
- The function name is taken as the first whitespace-delimited word of `<signature>`.

**Body blocks** follow the `@brief` line. All contiguous comment lines up to the function definition are collected; blank comment lines (`#` on its own) act as block separators.

```bash
# @brief myfunc <arg> — Short description.
#
# Optional paragraph with more detail.
# Can span multiple lines.
#
# Args:
#   <arg>        What the argument means.
#   --flag <v>   What the flag does.
#
# Env:
#   MY_VAR  Environment variable description.
#
# Stdout: what is printed to stdout.
#
# Returns: exit codes and their meaning.
myfunc() {
  ...
}
```

### Body block types

The generator classifies each block (group of lines between blank comment lines) into one of two types:

**Paragraph block** — plain prose. Rendered as a paragraph of text.

```bash
# All arguments are forwarded to `jq` unchanged.
```

**Section block** — a labelled heading. Two forms are recognised:

| Form | Syntax | When to use |
|------|--------|-------------|
| Multi-item | `Label:` on its own line; each item indented by **≥ 2 spaces** | `Args:` / `Parameters:` / `Env:` |
| Inline | `Label: text` as the **only line** in the block | `Stdout:` / `Returns:` |

The label must start with an uppercase letter and contain only letters (`[A-Za-z]+`) followed by a colon. Recognised labels and how they render:

| Comment label | Rendered heading | Rendered style |
|---------------|------------------|----------------|
| `Args:` | **Parameters** | Definition list |
| `Parameters:` | **Parameters** | Definition list |
| `Env:` | **Environment** | Definition list |
| `Stdout:` | **Stdout** | Plain text |
| `Returns:` | **Returns** | Plain text |

Any other `Word:` label is passed through as-is.

**Definition list items** (under `Args:` / `Parameters:` / `Env:`) are split into name and description on **two or more consecutive spaces**. The name is wrapped in backticks; the description becomes the definition term body.

```bash
# Args:
#   <key>         Top-level object key to extract.
#   --verbose     Print extra diagnostics.
```

Renders as:

```markdown
### Parameters

`<key>`
: Top-level object key to extract.

`--verbose`
: Print extra diagnostics.
```

### Rendered output structure

For reference, the full structure the generator produces for a module:

```markdown
# `<module-name>`

<module summary>

<module long description>

## `<function-name>`

<one-line description from @brief>

`​`​`bash
<signature>
`​`​`

<paragraph blocks>

### Parameters

`<name>`
: <description>

### Environment

`<VAR>`
: <description>

### Stdout

<inline text>

### Returns

<inline text>
```

Functions appear in source order. A function with no body blocks after its `@brief` line produces only the heading, description, and signature code block.
