# Library Unit Tests

Unit tests for `lib/` live under `test/lib/`. Each `.bats` file covers one module. Tests run without Docker by sourcing lib files directly into the bats test process. The full suite runs on both Linux and macOS in CI.

## Vendor Libraries

BATS and its companion libraries are git submodules at `test/lib/bats/`. Initialise once after cloning:

```bash
git submodule update --init --recursive
```

Never edit files under `test/lib/bats/` — they are vendored.

| Submodule | Purpose |
|-----------|---------|
| `bats-core` | Test runner |
| `bats-support` | Failure output formatting |
| `bats-assert` | `assert_success`, `assert_output`, etc. |
| `bats-file` | `assert_file_exists`, `assert_dir_exists`, etc. |

## Test Tiers

The suite has two tiers:

- **Lean tier (default):** `test/lib/*.bats` only. Suitable for distro containers that install just `bash`. Run by `just test-lib` and all CI library jobs.
- **Integration tier:** `test/lib/integration/*.bats`. Requires real `git`, `jq`, and other tools to be present. Enable with `bash .dev/scripts/test/run-unit.sh --integration`.

## File Anatomy

```bash
# Load BATS companion libraries first.
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# Load project helpers.
load helpers/common   # provides reload_lib()
load helpers/stubs    # provides create_fake_bin(), begin/end_path_isolation()

# Reload the module under test before each test for a clean state.
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

## `reload_lib`

**`reload_lib <module.sh>`** — defined in `helpers/common.bash`. Call it in `setup()` to give every test a clean module state. It:

1. Clears all `_LIB_*_LOADED` guard variables so the module re-sources.
2. Unsets all cached globals (`_OS__KERNEL`, `_NET_FETCH_TOOL`, `_OSPKG_DETECTED`, etc.).
3. For `ospkg.sh`: pre-declares `_OSPKG_OS_RELEASE` as a **global** associative array (`declare -gA`) before sourcing — see [ospkg.sh scoping workaround](#ospkgsh-scoping-workaround).
4. Sources `${LIB_ROOT}/<module.sh>`.

```bash
setup() {
  reload_lib ospkg.sh   # works for any module
}
```

To test load-guard idempotency, call `reload_lib` in `setup()` then source the file directly inside the test — the guard prevents re-sourcing.

### ospkg.sh Scoping Workaround

`ospkg.sh` contains `declare -A _OSPKG_OS_RELEASE=()`. When a file is sourced from **within a bash function**, `declare` without `-g` creates a **local** variable that disappears when the function returns. Without the workaround, tests that rely on `_OSPKG_OS_RELEASE` after `reload_lib` returns would see an undeclared variable.

`reload_lib` pre-empts this by running `declare -gA _OSPKG_OS_RELEASE=()` before the `source` call. Always use `reload_lib` rather than sourcing `ospkg.sh` directly in test setup.

## Stubbing Commands

`helpers/stubs.bash` provides three helpers:

**`create_fake_bin <name> [stdout]`** + **`prepend_fake_bin_path`** — create a stub under `$BATS_TEST_TMPDIR/bin/` and prepend it to PATH:

```bash
create_fake_bin "curl" "fake-response"
create_fake_bin "apt-get" ""
prepend_fake_bin_path
```

Stubs are scoped to `$BATS_TEST_TMPDIR` (cleaned up by bats after each test).

**`begin_path_isolation [cmd...]`** / **`end_path_isolation`** — swap PATH to `$BATS_TEST_TMPDIR/bin` and optionally allow through explicit commands. Use when you need to prove a tool is absent even when the host/runner has it installed:

```bash
begin_path_isolation "mkdir" "cat" "bash"
run _json__ensure_jq
end_path_isolation
```

Prefer this over ad-hoc PATH save/restore to keep tests deterministic across machines.

## Overriding Commands with Shell Functions

```bash
uname() { printf 'Darwin\n'; }
export -f uname   # required: makes the override visible inside sourced lib files
```

`export -f` is essential — without it, the library's call to `uname` resolves to the real binary.

## Mocking Library Functions

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

`logging__setup` runs `exec 3>&1 4>&2` and redirects installer stdout into a FIFO mux. Bats uses fd 3 for TAP output — running setup in the test process corrupts reporting.

**Rule:** Every test calling `logging__setup` or `logging__cleanup` must run in a `bash -c` subprocess.

After setup, plain `echo` goes to the mux (not bats stdout). Use `echo … >&3` for assertions **before** `logging__cleanup`, or plain `echo` **after** cleanup when fds 1/2 are restored. Set `LOG_FILE` (and `LOG_FILE_LEVEL` if needed) **before** `logging__setup` so the journal captures live output. To assert console lines while setup is active, `exec 2>'${_stderr}'` at the start of the subprocess so saved fd 4 points at your capture file. Do not use bats `4>file` on `run` — setup's `exec 4>&2` overwrites that redirect.

```bash
@test "logging__setup creates a temp log file" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    logging__setup
    [[ -f \"\${_LOGGING__LOG_FILE_TMP}\" ]] && echo OK >&3
    logging__cleanup
  "
  assert_success
  assert_output "OK"
}
```

Dual-threshold tests should set `LOG_FILE` before setup and compare console capture vs appended `LOG_FILE` content. This isolation is specific to `logging.sh`.

**Session scratch:** Installer temp files use `_FILE__SESSION_ROOT` from `lib/file.sh` (initialised in `__init__` via `file__session_ensure`). In unit tests, pin paths with `export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"` — do **not** set `_FILE__SESSION_OWNED`; `file__session_cleanup` will not `rm -rf` an injected root. After `logging__cleanup`, call `file__session_cleanup` when the test created owned scratch (mirrors installer `__exit__`).

## `run` vs Direct Calls

| Situation | Approach |
|-----------|---------|
| Checking exit code or stdout | `run <function> [args]`; then `assert_success` / `assert_output` |
| Checking global state after the call | Call directly (no `run`); inspect globals afterward |
| Function modifies PATH or env | Call directly; `run` only for the return-value check |

`run` captures stdout/stderr and exit code but executes in a subshell — global state changes are invisible to the test body after `run` returns.

## Writing New Tests

1. Open (or create) `test/lib/<module>.bats`.
2. Add `reload_lib <module>.sh` in `setup()` unless testing idempotency.
3. Stub any external commands the function invokes.
4. Use `run` for exit-code/stdout assertions; call directly for global-state assertions.
5. One observable behaviour per `@test`.
6. Run `bash .dev/scripts/test/run-unit.sh --module <name> --jobs 1` before committing.

## Running Tests Locally

```bash
just test-lib                                        # all modules
bash .dev/scripts/test/run-unit.sh --module os       # single module
bash .dev/scripts/test/run-unit.sh --filter "platform"  # filter by test-name regex
bash .dev/scripts/test/run-unit.sh --jobs 1          # serial (for debugging)
test/lib/bats/bats-core/bin/bats test/lib/os.bats    # direct bats (no sync step)

# Integration tier (requires real git, jq, etc.)
bash .dev/scripts/test/run-unit.sh --integration
```

## macOS Considerations

macOS ships bash 3.2 (GPL licence change). All `lib/` modules require bash ≥4.

`.dev/scripts/test/run-unit.sh` handles this automatically: it detects `BASH_VERSINFO[0] < 4`, finds `/opt/homebrew/bin/bash` (Apple Silicon) or `/usr/local/bin/bash` (Intel), and re-execs itself. Install bash ≥4 locally: `brew install bash`.

macOS-specific values to assert explicitly:

| Function | macOS value |
|----------|-------------|
| `os__kernel` | `Darwin` |
| `os__platform` | `macos` |
| `os__font_dir` (root) | `/Library/Fonts` |
| `os__font_dir` (non-root) | `${HOME}/Library/Fonts` |

macOS has no `/etc/os-release`; `os__id`, `os__id_like`, and `os__platform` fall through to the `uname -s` path.

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| `declare -A` in sourced file creates local var | All ospkg platform lookups return same value | `reload_lib` pre-declares `declare -gA _OSPKG_OS_RELEASE=()` |
| `logging__setup` hijacks fd 3 | Only 1 of N logging tests runs; bats prints "Bad file descriptor" | Wrap every logging test in `run bash -c "..."` |
| Real tool found despite fake bin prepend | Function ignores stub | Use `begin_path_isolation` to hide the real binary entirely |
| PATH left restricted after test | Bats teardown `rm: command not found` | Always `end_path_isolation` or restore PATH before function returns |
| `export -f` missing | Override invisible inside sourced library | Add `export -f <funcname>` after defining the function |
| Global state leaking between tests | Tests pass alone but fail in suite | Call `reload_lib` in `setup()` for every test needing clean state |

## CI

Library unit tests run via two jobs triggered by changes to `lib/**` or `test/lib/**`:

| Job | How it runs |
|-----|-------------|
| Linux matrix | ubuntu-latest runner; each environment from `test/lib/scenarios.yaml` (Ubuntu, Debian, Fedora, Rocky, Alpine, openSUSE, Arch) runs in its own Docker container |
| macOS | Native macOS runners; bash ≥4 installed via `brew install bash` automatically by CI |

Local macOS runs handle the bash ≥4 requirement via the re-exec in `run-unit.sh`.
