# Library Tests

Unit tests for `lib/` live under `test/lib/`. Each `.bats` file covers one module.

Tests run without Docker by sourcing lib files directly into the bats test process. The full suite runs on both Linux and macOS in CI.

## Vendor Libraries

bats-core and its companion libraries are git submodules at `test/lib/bats/`. Initialise once after cloning:

```bash
git submodule update --init --recursive
```

Never edit files under `test/lib/bats/` — they are vendored.

| Submodule | Purpose |
|---|---|
| `bats-core` | Test runner |
| `bats-support` | Failure output formatting |
| `bats-assert` | `assert_success`, `assert_output`, etc. |
| `bats-file` | `assert_file_exists`, `assert_dir_exists`, etc. |

## File Anatomy

```bash
# Load bats companion libraries BEFORE any `load` calls.
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# Load project helpers.
load helpers/common   # provides reload_lib()
load helpers/stubs    # provides create_fake_bin(), prepend_fake_bin_path()

# Reload the library under test before each test for a clean state.
setup() {
  reload_lib os.sh
}

@test "os__kernel returns the uname output" {
  uname() { printf 'Linux\n'; }
  export -f uname
  run os__kernel
  assert_success
  assert_output "Linux"
}
```

## reload_lib

**`reload_lib <module.sh>`** — defined in `helpers/common.bash`. Call it in `setup()` to give every test a clean module state. It:

1. Clears all `_LIB_*_LOADED` guard variables so the module re-sources.
2. Unsets all cached globals (`_OS__KERNEL`, `_NET_FETCH_TOOL`, `_OSPKG_DETECTED`, etc.).
3. For `ospkg.sh` specifically: pre-declares `_OSPKG_OS_RELEASE` as a **global** associative array with `declare -gA` **before** sourcing — see [ospkg.sh scoping workaround](#ospkgsh-scoping-workaround).
4. Sources `${LIB_ROOT}/<module.sh>`.

```bash
setup() {
  reload_lib ospkg.sh   # works for any module
}
```

To test the load-guard (idempotency), call `reload_lib` in `setup()` then source the file directly inside the test without calling `reload_lib` again — the guard variable will prevent re-sourcing.

### ospkg.sh Scoping Workaround

`ospkg.sh` contains `declare -A _OSPKG_OS_RELEASE=()`. When a file is sourced from **within a bash function**, `declare` without `-g` creates a **local** variable that disappears when the function returns. Without the workaround, every test that relies on `_OSPKG_OS_RELEASE` after `reload_lib` returns would see an undeclared variable — bash silently treats it as an indexed array, all non-integer keys map to `[0]`, and the last write wins (typically the arch value from `uname -m`).

`reload_lib` pre-empts this by running `declare -gA _OSPKG_OS_RELEASE=()` before the `source` call. The global declaration ensures the array exists at the correct scope. Always use `reload_lib` rather than sourcing `ospkg.sh` directly in test setup.

## Stubbing Commands

`helpers/stubs.bash` provides two helpers:

```bash
# Create ${BATS_TEST_TMPDIR}/bin/<name> — prints <stdout> and exits 0.
create_fake_bin "curl" "fake-response"
create_fake_bin "apt-get" ""          # prints nothing

# Prepend fake bin dir to PATH so fakes shadow real commands.
prepend_fake_bin_path
```

Stubs are scoped to `$BATS_TEST_TMPDIR`, which bats cleans up after each test.

### Replacing PATH Entirely

When the real command must be completely hidden — for example, testing wget detection while `curl` is installed on the host:

```bash
@test "detects wget when curl is absent" {
  reload_lib net.sh
  create_fake_bin "wget" ""
  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"   # only fake bin — real curl invisible
  net__ensure_fetch_tool
  local _result="$_NET_FETCH_TOOL"
  export PATH="$_saved"                   # restore before bats teardown uses rm, etc.
  [[ "$_result" == "wget" ]]
}
```

**Always restore PATH before the test function returns.** Bats teardown uses `rm` and other tools that require a real PATH. If PATH is left restricted, bats prints `rm: command not found` warnings during cleanup (tests still pass, but the output is noisy).

## Overriding Commands with Shell Functions

bash built-ins and external commands can be overridden by defining a function with the same name:

```bash
uname() { printf 'Darwin\n'; }
export -f uname   # make visible in sourced files
```

`export -f` is required whenever the function must be visible inside a sourced library file. Without it, the library's call to the command resolves to the real binary.

For commands where a function override is awkward (requires parsing arguments), prefer `create_fake_bin` + `prepend_fake_bin_path` instead.

## Mocking Library Functions

To mock a lib function called by the function under test, define it in the test body before invoking the real function:

```bash
@test "github__latest_tag parses tag_name from JSON" {
  reload_lib net.sh
  reload_lib github.sh
  github__fetch_release_json() {
    printf '{"tag_name":"v1.2.3"}\n'
    return 0
  }
  export -f github__fetch_release_json
  run github__latest_tag "owner/repo"
  assert_success
  assert_output "v1.2.3"
}
```

## Subprocess Isolation for `logging.sh`

`logging__setup` executes `exec 3>&1 4>&2`, which redirects file descriptor 3. Bats uses fd 3 for TAP output — the redirect corrupts bats' reporting and causes most tests in the file to silently vanish.

**Rule:** Every test that calls `logging__setup` or `logging__cleanup` must run in a `bash -c` subprocess isolated from bats' fd 3:

```bash
@test "logging__setup creates a temp log file" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    logging__setup
    [[ -f \"\${_LOGGING_TMPFILE}\" ]] && echo OK
  "
  assert_success
  assert_output "OK"
}
```

This isolation is specific to `logging.sh`. Other modules do not need it.

## Using `run` vs Direct Calls

| Situation | Approach |
|---|---|
| Checking exit code or stdout | `run <function> [args]`; then `assert_success` / `assert_output` |
| Checking global state after the call | Call directly (no `run`); inspect globals afterward |
| Function modifies PATH or env | Call directly; inspect with `[[ ... ]]`; use `run` only for the return-value check |

`run` captures stdout/stderr and the exit code but executes in a subshell — changes to exported variables or global state are invisible to the test body after `run` returns.

## Writing New Tests

1. Open `test/lib/<module>.bats` for the module you changed.
2. Add `reload_lib <module>.sh` in `setup()` unless the test explicitly checks idempotency.
3. Stub any external commands the function invokes.
4. Use `run` for exit-code / stdout assertions; call directly for global-state assertions.
5. One observable behaviour per `@test`.
6. Run `bash .dev/scripts/test/run-unit.sh --module <name> --jobs 1` before committing.

## Running Tests Locally

```bash
# All modules (also runs scripts/sync-src.py first)
just test-lib

# Single module
bash .dev/scripts/test/run-unit.sh --module os

# Filter by test name (regex)
bash .dev/scripts/test/run-unit.sh --filter "platform"

# Serial output — useful for debugging
bash .dev/scripts/test/run-unit.sh --jobs 1

# Direct bats invocation — skips scripts/sync-src.py, useful for iteration
test/lib/bats/bats-core/bin/bats test/lib/os.bats
```

## macOS Considerations

macOS ships bash 3.2 due to the GPL licence change in bash 4+. All lib/ modules require bash ≥4.

`.dev/scripts/test/run-unit.sh` handles this automatically:

1. Detects `BASH_VERSINFO[0] < 4`.
2. Tries `/opt/homebrew/bin/bash` (Apple Silicon) then `/usr/local/bin/bash` (Intel).
3. Re-execs itself under the first bash ≥4 found.
4. Prepends that executable's directory to `PATH` so `#!/usr/bin/env bash` sub-scripts (bats-exec-test, bats-exec-suite) also resolve to bash ≥4.

Install bash ≥4 locally: `brew install bash`. The CI `macos-latest` runner has Homebrew bash pre-installed.

macOS-specific return values to test for explicitly:

| Function | macOS value |
|---|---|
| `os__kernel` | `Darwin` |
| `os__platform` | `macos` |
| `os__font_dir` (as root) | `/Library/Fonts` |
| `os__font_dir` (non-root, no `$XDG_DATA_HOME`) | `${HOME}/Library/Fonts` |

macOS has no `/etc/os-release`, so `os__id`, `os__id_like`, and `os__platform` fall through to the `uname -s` path.

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| `declare -A` in sourced file creates local var | All ospkg platform lookups return the same value | `reload_lib` pre-declares `declare -gA _OSPKG_OS_RELEASE=()` before sourcing |
| `logging__setup` hijacks fd 3 | Only 1 of N logging tests runs; bats prints "Bad file descriptor" | Wrap every logging test in `run bash -c "..."` |
| Real `curl` found despite fake bin prepend | `net__ensure_fetch_tool` always returns `curl` even in the wget test | Replace PATH entirely (`export PATH="${BATS_TEST_TMPDIR}/bin"`); restore afterward |
| PATH left restricted | Bats teardown `rm: command not found` | Always `export PATH="$_saved"` before the test function returns |
| `export -f` missing | Overridden function invisible inside sourced library | Add `export -f <funcname>` after defining the override |
| Global state leaking between tests | Tests pass individually but fail in suite | Call `reload_lib` in `setup()` for every test that needs a clean module state |


## Unit tests for lib/

### Overview

In addition to the container-based feature scenarios, the shared bash library
under `lib/` has a dedicated [bats](https://bats-core.readthedocs.io/) unit
test suite. The suite tests every public function in every module without
requiring Docker, making it fast and runnable on both Linux and macOS.

The vendor libraries (bats-core, bats-support, bats-assert, bats-file) live
as git submodules under `test/lib/bats/` and are checked out with
`git clone --recurse-submodules` or `git submodule update --init --recursive`.

### Directory layout

```
test/lib/
  setup_suite.bash        bash ≥4 guard — auto-discovered by bats
  <module>.bats           one test file per lib/ module
  helpers/
    common.bash           bats library loader + reload_lib() helper
    stubs.bash            create_fake_bin() / prepend_fake_bin_path()
  bats/                   ← git submodules, never edit
    bats-core/
    bats-support/
    bats-assert/
    bats-file/
```

Module coverage:

| Test file | lib/ module | Tests |
|---|---|---|
| `os.bats` | `os.sh` | 28 |
| `shell.bats` | `shell.sh` | 61 |
| `str.bats` | `str.sh` | 3 |
| `ospkg.bats` | `ospkg.sh` | 28 |
| `logging.bats` | `logging.sh` | 6 |
| `net.bats` | `net.sh` | 11 |
| `json.bats` | `json.sh` | 8 |
| `git.bats` | `git.sh` | 6 |
| `checksum.bats` | `checksum.sh` | 6 |
| `github.bats` | `github.sh` | 47 |
| `users.bats` | `users.sh` | 13 |

### Running unit tests

```bash
# Run all modules
just test-lib

# Run a single module
bash .dev/scripts/test/run-unit.sh --module os

# Filter by test-name regex
bash .dev/scripts/test/run-unit.sh --filter "platform"

# Serial execution (useful for debugging output)
bash .dev/scripts/test/run-unit.sh --jobs 1

# Run integration-only bats files (requires real jq/git toolchain)
SYSSET_RUN_INTEGRATION_DEPS=1 bash .dev/scripts/test/run-unit.sh --integration

# Run an explicit path or directory of bats files
bash .dev/scripts/test/run-unit.sh --paths test/lib/integration
```

`.dev/scripts/test/run-unit.sh` automatically re-execs itself under bash ≥4 on macOS
(where `/bin/bash` is 3.2 due to the GPL licence change), so it works
correctly without any pre-flight setup on a stock Mac with Homebrew bash.

The suite uses a two-tier model:

- **Lean tier (default):** runs top-level `test/lib/*.bats` only, suitable for
  distro containers that install just `bash`.
- **Integration tier:** runs `test/lib/integration/*.bats` and is intended for
  environments where real `git`/`jq` are available. Enable with
  `SYSSET_RUN_INTEGRATION_DEPS=1` and `--integration`.

### Test anatomy

Each test file starts by sourcing the helpers:

```bash
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file
load helpers/common
load helpers/stubs
```

**`reload_lib <module.sh>`** — defined in `helpers/common.bash`. It clears all
lib load-guards and relevant cached globals, then `source`s the module. Call
it in `setup()` or at the top of individual tests that need a clean module
state:

```bash
setup() {
  reload_lib os.sh
}
```

**`create_fake_bin <name> [stdout]`** and **`prepend_fake_bin_path`** — defined
in `helpers/stubs.bash`. They create a small stub executable under
`$BATS_TEST_TMPDIR/bin/` and prepend that directory to `PATH`, so tests can
control what commands like `curl`, `wget`, `git`, or `apt-get` return without
touching the real system:

```bash
setup() {
  reload_lib net.sh
  create_fake_bin curl ""
  prepend_fake_bin_path
}
```

**`begin_path_isolation [allowed_cmd...]`** and **`end_path_isolation`** —
also defined in `helpers/stubs.bash`. Use this pair for lean-tier tests that
must prove a tool is absent even when the host/runner has it installed. The
helper swaps `PATH` to `$BATS_TEST_TMPDIR/bin` and optionally injects explicit
pass-through commands (for example `mkdir`, `cat`, `bash`) so only the tools
you allow remain visible to the test.

```bash
begin_path_isolation "mkdir" "cat" "bash"
run _json__ensure_jq
end_path_isolation
```

Prefer this helper over ad-hoc `PATH` save/restore snippets. It keeps lean
unit tests deterministic across local machines and CI runners.

**`bash -c` subprocess isolation** — modules that manipulate file descriptors
(e.g. `logging__setup` redirects fd 3 and 4) must be tested in isolated
subprocesses to avoid interfering with bats' own TAP output on fd 3:

```bash
@test "logging__setup creates a temp log file" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    [[ -f \"\${_LOGGING_TMPFILE}\" ]] && echo OK
  "
  assert_success
  assert_output "OK"
}
```

### Writing new unit tests

When adding or changing a function in `lib/`:

1. Open (or create) `test/lib/<module>.bats`.
2. Add a `@test` block. Prefer calling `reload_lib` in `setup()` to isolate
   each test; only skip it for tests that explicitly check idempotency or
   cached-state behaviour.
3. Use `assert_success`, `assert_failure`, `assert_output`, `assert_line`, etc.
   from bats-assert. Use `assert_file_exists` etc. from bats-file.
4. Keep each test focused on one behaviour. One test per distinct outcome
   (success path, failure path, edge case) is the right granularity.
5. Run `just test-lib` (or `bash .dev/scripts/test/run-unit.sh --module <name>`) to verify
   before committing.

### Unit test CI

The `unit-native` and `unit-linux` jobs in `ci.yaml` run on every push or PR that touches `lib/**` or `test/lib/**`. Two job groups run in parallel — no per-module discovery:

| Job | Environment | Notes |
|---|---|---|
| `unit-native` | ubuntu-latest + macos-latest | Installs bash ≥4 on macOS via `brew install bash` |
| `unit-linux` | debian:bookworm, fedora:latest, rockylinux:9, alpine:3.20 containers | Validates glibc and musl compatibility |

The GHA `macos-latest` runner does **not** have bash ≥4 pre-installed; `ci.yaml` adds an explicit `brew install bash` step before running the suite. `.dev/scripts/test/run-unit.sh` handles the re-exec automatically for local runs.

```bash
# Trigger all unit tests manually (runs all CI including unit tests)
gh workflow run "CI"

# Watch the run
gh run watch
```

Run `just test-lib` before pushing changes to `lib/` or `test/lib/`; CI runs the same suite when those paths change.

