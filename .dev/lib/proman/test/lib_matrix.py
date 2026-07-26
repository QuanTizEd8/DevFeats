"""Orchestrate lib/ tests across logical platforms and isolated profiles."""

from __future__ import annotations

import os
import re
import selectors
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from concurrent.futures import Future, ThreadPoolExecutor, wait
from contextlib import suppress
from dataclasses import dataclass
from pathlib import Path
from typing import Any, BinaryIO

from proman.config import load as load_config

from .environments import load as load_envs
from .environments import resolve
from .lib_scenarios import PROFILES, LibScenarioError, load_and_validate

_TIERS = frozenset({"lean", "integration", "all"})
_WORKLOADS = frozenset({"ordinary", "bootstrap", "complete"})


@dataclass(frozen=True)
class ProfileResult:
    """Result metadata for one profile and its test-command output spool.

    ``log_path`` contains the test-command bytes used for replay and summary
    parsing. In live-stream mode environment-resolution output is deliberately
    written only to the live console, not duplicated into this spool.
    """

    platform: str
    profile: str
    env_name: str
    returncode: int
    log_path: Path
    # True when this profile's output was streamed live (single-platform runs),
    # so the end-of-run replay skips it instead of printing it a second time.
    streamed: bool = False


@dataclass(frozen=True)
class RunnerContext:
    """Host/container paths shared by every profile in one invocation."""

    host_root: str
    run_in_container: str
    lib_root: str | None
    lib_bind: str | None


class ProcessRegistry:
    """Track cancellable child process groups across platform workers."""

    def __init__(self, cancel_event: threading.Event) -> None:
        self._cancel_event = cancel_event
        self._lock = threading.Lock()
        self._processes: set[subprocess.Popen[str]] = set()
        self._container_names: set[str] = set()

    def add(self, proc: subprocess.Popen[str]) -> None:
        """Register a subprocess and stop it immediately if already cancelled."""
        with self._lock:
            self._processes.add(proc)
            cancelled = self._cancel_event.is_set()
        if cancelled:
            self.terminate(proc)

    def discard(self, proc: subprocess.Popen[str]) -> None:
        """Forget a completed subprocess."""
        with self._lock:
            self._processes.discard(proc)

    def register_container(self, name: str) -> None:
        """Register an exact container name for bounded cleanup."""
        with self._lock:
            self._container_names.add(name)

    def terminate_all(self) -> None:
        """Stop every registered process tree and remove known containers."""
        with self._lock:
            processes = tuple(self._processes)
            container_names = tuple(sorted(self._container_names))
        for proc in processes:
            self._signal(proc, signal.SIGTERM)
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline and any(
            proc.poll() is None for proc in processes
        ):
            time.sleep(0.02)
        for proc in processes:
            if proc.poll() is None:
                self._signal(proc, signal.SIGKILL)
        for proc in processes:
            with suppress(subprocess.TimeoutExpired):
                proc.wait(timeout=0.2)
        self._remove_containers(container_names)
        time.sleep(0.1)
        self._remove_containers(container_names)

    @staticmethod
    def terminate(proc: subprocess.Popen[str]) -> None:
        """Stop one subprocess tree."""
        if proc.poll() is not None:
            return
        try:
            if os.name == "posix":
                os.killpg(proc.pid, signal.SIGTERM)
            else:
                proc.terminate()
            proc.wait(timeout=1)
        except ProcessLookupError:
            return
        except subprocess.TimeoutExpired:
            try:
                if os.name == "posix":
                    os.killpg(proc.pid, signal.SIGKILL)
                else:
                    proc.kill()
            except ProcessLookupError:
                return
            proc.wait(timeout=1)

    @staticmethod
    def _signal(proc: subprocess.Popen[str], sig: signal.Signals) -> None:
        if proc.poll() is not None:
            return
        try:
            if os.name == "posix":
                os.killpg(proc.pid, sig)
            elif sig == signal.SIGTERM:
                proc.terminate()
            else:
                proc.kill()
        except ProcessLookupError:
            pass

    @staticmethod
    def _remove_containers(names: tuple[str, ...]) -> None:
        if not names:
            return
        with suppress(FileNotFoundError, subprocess.TimeoutExpired):
            subprocess.run(
                ["docker", "container", "rm", "-f", *names],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=1,
            )


def _runner_context() -> tuple[RunnerContext | None, str]:
    """Resolve host/container paths and validate an ambient library artifact."""
    cfg = load_config()
    root = Path(cfg.root_path).resolve()
    host_root = Path(os.environ.get("HOST_REPO_ROOT", str(root))).resolve()
    context = RunnerContext(
        host_root=str(host_root),
        run_in_container=str(cfg.absolute_path("path.test_run_in_container")),
        lib_root=None,
        lib_bind=None,
    )
    ambient_lib_root = os.environ.get("LIB_ROOT")
    if not ambient_lib_root:
        return context, ""

    raw_lib_root = Path(ambient_lib_root)
    if not raw_lib_root.is_absolute():
        return None, "LIB_ROOT must be an absolute path within the repository root."
    resolved_lib_root = raw_lib_root.resolve()
    try:
        relative = resolved_lib_root.relative_to(root)
    except ValueError:
        return None, "LIB_ROOT must be an absolute path within the repository root."
    init_path = resolved_lib_root / "__init__.bash"
    if (
        not resolved_lib_root.is_dir()
        or not init_path.is_file()
        or init_path.is_symlink()
    ):
        return (
            None,
            "LIB_ROOT must be a library directory containing a regular "
            "__init__.bash file.",
        )

    child_lib_root = Path("/repo") / relative
    default_child_lib = Path("/repo/lib")
    lib_bind = None
    if child_lib_root != default_child_lib:
        host_lib_root = host_root / relative
        lib_bind = f"{host_lib_root}:{child_lib_root}:ro"
    return (
        RunnerContext(
            host_root=str(host_root),
            run_in_container=context.run_in_container,
            lib_root=str(child_lib_root),
            lib_bind=lib_bind,
        ),
        "",
    )


def _profiles_for(workload: str) -> tuple[str, ...]:
    if workload == "complete":
        return PROFILES
    return (workload,)


def _validate_forwarded_args(workload: str, args: list[str]) -> str:
    """Validate the deliberately small run-unit remainder grammar."""
    allowed = {"--filter"}
    if workload == "ordinary":
        allowed.update({"--module", "--jobs"})
    index = 0
    while index < len(args):
        token = args[index]
        option, separator, value = token.partition("=")
        if option not in allowed:
            return f"{option or token} is not available in {workload} matrix mode."
        if separator:
            if option != "--filter":
                return f"{option} requires its value as a separate argument."
            if not value:
                return f"{option} requires a non-empty value."
            index += 1
            continue
        if index + 1 >= len(args) or args[index + 1].startswith("-"):
            return f"{option} requires a non-option value."
        index += 2
    return ""


def _cancel_executor(
    executor: ThreadPoolExecutor,
    futures: dict[str, Future[list[ProfileResult]]],
    cancel_event: threading.Event,
    registry: ProcessRegistry,
) -> None:
    """Cancel every worker and prove that all worker threads have returned."""
    cancel_event.set()
    for future in futures.values():
        future.cancel()
    registry.terminate_all()
    _done, pending = wait(tuple(futures.values()), timeout=3)
    if pending:
        registry.terminate_all()
        _done, pending = wait(pending, timeout=2)
    if pending:
        platforms = ", ".join(
            platform for platform, future in futures.items() if future in pending
        )
        # This is a fatal internal invariant: _run_platform may only block in
        # resolve() or _run_profile(), and both are wired to this cancellation
        # event plus ProcessRegistry. Reaching this means a future worker change
        # introduced an uncancellable operation and must not be hidden.
        message = (
            "Fatal matrix cancellation invariant violated; workers did not stop: "
            f"{platforms}"
        )
        raise RuntimeError(message)
    # Every task is now done or was cancelled, so this cannot block on workers.
    executor.shutdown(wait=True, cancel_futures=True)


def _validate_options(
    workload: str,
    ordinary_tier: str,
    matrix_jobs: int,
    extra_args: list[str],
) -> str:
    error = ""
    if workload not in _WORKLOADS:
        error = f"Invalid workload: {workload!r}"
    elif ordinary_tier not in _TIERS:
        error = f"Invalid ordinary tier: {ordinary_tier!r}"
    elif (
        not isinstance(matrix_jobs, int)
        or isinstance(matrix_jobs, bool)
        or matrix_jobs < 1
    ):
        error = "--matrix-jobs must be a positive integer."
    else:
        error = _validate_forwarded_args(workload, extra_args)
    return error


def _build_profile_command(
    platform: str,
    profile_name: str,
    profile: dict[str, Any],
    ordinary_tier: str,
    image: str,
    extra_args: list[str],
    invocation_token: str,
    context: RunnerContext,
) -> list[str]:
    """Build the container command for one validated concrete profile."""
    cmd = [
        "bash",
        context.run_in_container,
        "--image",
        image,
        "--name",
        f"test-lib-{invocation_token}-{platform}-{profile_name}",
        "--bind",
        f"{context.host_root}/lib:/repo/lib:ro",
        "--bind",
        f"{context.host_root}/test/lib:/repo/test/lib:ro",
        "--bind",
        f"{context.host_root}/.dev/scripts/test:/repo/.dev/scripts/test:ro",
        "--bind",
        f"{context.host_root}/features/install-os-pkg/manifest.schema.json:/repo/features/install-os-pkg/manifest.schema.json:ro",
        "--bind",
        f"{context.host_root}/features/install-git-lfs/files/post-create--configure-and-pull.sh"
        ":/repo/features/install-git-lfs/files/post-create--configure-and-pull.sh:ro",
    ]
    if context.lib_bind is not None:
        cmd += ["--bind", context.lib_bind]
    for key, value in profile.get("env_vars", {}).items():
        cmd += ["--env", f"{key}={value}"]
    if context.lib_root is not None:
        cmd += ["--env", f"LIB_ROOT={context.lib_root}"]

    run_unit_parts = ["bash", "/repo/.dev/scripts/test/run-unit.sh"]
    if profile_name == "bootstrap":
        run_unit_parts += ["--path", "/repo/test/lib/bootstrap/bootstrap.bats"]
    else:
        run_unit_parts += ["--tier", ordinary_tier]
    run_unit_parts += extra_args
    cmd += ["--run", f"cd /repo && {shlex.join(run_unit_parts)}"]
    return cmd


def _run_profile(  # noqa: PLR0913
    platform: str,
    profile_name: str,
    profile: dict[str, Any],
    ordinary_tier: str,
    image: str,
    extra_args: list[str],
    invocation_token: str,
    context: RunnerContext,
    log_path: Path,
    cancel_event: threading.Event,
    registry: ProcessRegistry,
    stream: bool,  # noqa: FBT001
) -> ProfileResult:
    cmd = _build_profile_command(
        platform,
        profile_name,
        profile,
        ordinary_tier,
        image,
        extra_args,
        invocation_token,
        context,
    )
    registry.register_container(cmd[cmd.index("--name") + 1])
    if cancel_event.is_set():
        message = "Profile launch cancelled."
        raise InterruptedError(message)
    if stream:
        returncode = _run_streamed(cmd, log_path, cancel_event, registry)
    else:
        # A subprocess writes bytes directly to this descriptor; opening it as
        # binary makes that contract explicit and avoids implying Python encoding.
        with log_path.open("ab") as output:
            proc = subprocess.Popen(
                cmd,
                stdout=output,
                stderr=subprocess.STDOUT,
                text=True,
                start_new_session=os.name == "posix",
            )
            registry.add(proc)
            try:
                while proc.poll() is None:
                    if cancel_event.wait(0.05):
                        registry.terminate(proc)
                        break
                returncode = proc.wait()
            finally:
                registry.discard(proc)
    return ProfileResult(
        platform,
        profile_name,
        profile["env"],
        returncode,
        log_path,
        streamed=stream,
    )


def _run_streamed(
    cmd: list[str],
    log_path: Path,
    cancel_event: threading.Event,
    registry: ProcessRegistry,
) -> int:
    """Run a profile command, streaming its bytes to console and its spool.

    This is used only when workers are serial, so the live console cannot
    interleave profiles. The command spool remains byte-exact. A selector and
    ``os.read`` make short pipe writes visible immediately instead of waiting
    for Python's buffered ``read(n)`` to fill. The project only streams these
    subprocesses on POSIX hosts (Linux/macOS); fail explicitly elsewhere rather
    than quietly regressing to buffered output.
    """
    if os.name != "posix":
        message = "Live profile streaming requires a POSIX pipe reader."
        raise RuntimeError(message)

    # Opening before launch means every launched command has an established
    # spool destination, and an open failure cannot leave a child behind.
    with log_path.open("ab") as output:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        stdout = proc.stdout
        if stdout is None:
            message = "Live profile subprocess did not expose stdout."
            with suppress(BaseException):
                _terminate_and_reap_streamed(proc, registry)
            raise RuntimeError(message)
        try:
            registry.add(proc)
            binary_stdout = getattr(sys.stdout, "buffer", None)
            with selectors.DefaultSelector() as selector:
                selector.register(stdout, selectors.EVENT_READ)
                while True:
                    if cancel_event.is_set():
                        _terminate_and_reap_streamed(proc, registry)
                        return proc.wait()
                    events = selector.select(timeout=0.05)
                    if not events:
                        continue
                    for key, _mask in events:
                        chunk = os.read(key.fd, 65536)
                        if not chunk:
                            selector.unregister(stdout)
                            return proc.wait()
                        _write_stream_chunk(chunk, output, binary_stdout)
        except BaseException:
            # Do not abandon a process just because a capture/output/log/wait
            # operation failed. Preserve the original exception after the group
            # has been terminated and reaped.
            with suppress(BaseException):
                _terminate_and_reap_streamed(proc, registry)
            raise
        finally:
            registry.discard(proc)


def _terminate_and_reap_streamed(
    proc: subprocess.Popen[bytes], registry: ProcessRegistry
) -> None:
    """Terminate a streamed process even if the registry's graceful path errors."""
    try:
        registry.terminate(proc)
    finally:
        if proc.poll() is None:
            with suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)
            with suppress(subprocess.TimeoutExpired):
                proc.wait(timeout=1)


def _write_stream_chunk(
    chunk: bytes, output: BinaryIO, binary_stdout: BinaryIO | None
) -> None:
    """Write one streamed chunk, treating every short write as an output error."""
    if binary_stdout is not None:
        _require_full_stream_write(
            binary_stdout.write(chunk), len(chunk), "binary stdout"
        )
        binary_stdout.flush()
    else:
        text = chunk.decode("utf-8", errors="backslashreplace")
        _require_full_stream_write(sys.stdout.write(text), len(text), "text stdout")
        sys.stdout.flush()
    _require_full_stream_write(output.write(chunk), len(chunk), "profile spool")
    output.flush()


def _require_full_stream_write(written: int | None, expected: int, sink: str) -> None:
    """Reject file-like sinks that silently report a partial write."""
    if written is not None and written != expected:
        message = f"Short write to {sink}: wrote {written} of {expected} units."
        raise OSError(message)


def _run_platform(  # noqa: PLR0913
    platform: str,
    profiles: dict[str, dict[str, Any]],
    workload: str,
    ordinary_tier: str,
    extra_args: list[str],
    invocation_token: str,
    context: RunnerContext,
    envs: dict[str, Any],
    logs_dir: Path,
    cancel_event: threading.Event,
    registry: ProcessRegistry,
    stream: bool,  # noqa: FBT001
) -> list[ProfileResult]:
    """Resolve and run selected profiles serially for one platform."""
    results: list[ProfileResult] = []
    for profile_name in _profiles_for(workload):
        if cancel_event.is_set():
            break
        profile = profiles[profile_name]
        env_name = profile["env"]
        log_path = logs_dir / f"{platform}--{profile_name}.log"
        try:
            if stream:
                image = resolve(
                    env_name,
                    envs,
                    output=sys.stdout,
                    cancel_event=cancel_event,
                    process_started=registry.add,
                    process_finished=registry.discard,
                )
            else:
                with log_path.open("a", encoding="utf-8") as output:
                    image = resolve(
                        env_name,
                        envs,
                        output=output,
                        cancel_event=cancel_event,
                        process_started=registry.add,
                        process_finished=registry.discard,
                    )
        except InterruptedError:
            break
        except (Exception, SystemExit) as exc:  # noqa: BLE001 - aggregate resolution
            message = f"Environment resolution failed for {env_name!r}: {exc}\n"
            with log_path.open("a", encoding="utf-8") as output:
                output.write(message)
            if stream:
                sys.stdout.write(message)
            results.append(
                ProfileResult(
                    platform, profile_name, env_name, 1, log_path, streamed=stream
                )
            )
            continue
        if cancel_event.is_set():
            break
        try:
            result = _run_profile(
                platform,
                profile_name,
                profile,
                ordinary_tier,
                image,
                extra_args,
                invocation_token,
                context,
                log_path,
                cancel_event,
                registry,
                stream,
            )
        except InterruptedError:
            break
        except (Exception, SystemExit) as exc:  # noqa: BLE001 - aggregate worker failures
            with log_path.open("a", encoding="utf-8") as output:
                output.write(f"Profile runner failed: {exc}\n")
            result = ProfileResult(platform, profile_name, env_name, 1, log_path)
        results.append(result)
    return results


def _replay_log(log_path: Path) -> None:
    """Replay arbitrary subprocess bytes without letting decoding abort a matrix."""
    with log_path.open(encoding="utf-8", errors="backslashreplace") as output:
        shutil.copyfileobj(output, sys.stdout)


_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
# run-unit.sh prints one such line per profile (see its summary printf).
_SUMMARY_RE = re.compile(
    r"Summary:\s*(?P<completed>\d+)(?:/(?P<planned>\d+))?\s+completed"
    r"(?:\s+\(planned total unavailable\))?[^,]*,\s*"
    r"(?P<passed>\d+)\s+passed,\s*(?P<failed>\d+)\s+failed,\s*"
    r"(?P<skipped>\d+)\s+skipped,\s*(?P<todo>\d+)\s+TODO,\s*"
    r"(?:(?P<incomplete>\d+)\s+incomplete|incomplete count unavailable)"
)


def _profile_summary(log_path: Path) -> dict[str, int | None] | None:
    """Extract every run-unit summary count from a test-command spool."""
    if not log_path.is_file():
        return None
    text = _ANSI_RE.sub(
        "", log_path.read_text(encoding="utf-8", errors="backslashreplace")
    )
    match = None
    for match in _SUMMARY_RE.finditer(text):  # noqa: B007 - keep the last match
        pass
    if match is None:
        return None
    return {
        "completed": int(match["completed"]),
        "planned": int(match["planned"]) if match["planned"] is not None else None,
        "passed": int(match["passed"]),
        "failed": int(match["failed"]),
        "skipped": int(match["skipped"]),
        "todo": int(match["todo"]),
        "incomplete": (
            int(match["incomplete"]) if match["incomplete"] is not None else None
        ),
    }


def _print_test_total(results: list[ProfileResult]) -> None:
    """Print one rolled-up test total across every profile in the run.

    The per-profile ``Matrix:`` line counts profiles, not tests, so the last
    number on screen can look tiny (e.g. an 18-test bootstrap profile). This
    sums the actual test counts each profile reported so the true total is the
    final line.
    """
    summaries = [s for r in results if (s := _profile_summary(r.log_path))]
    if not summaries:
        return
    completed = sum(s["completed"] for s in summaries)
    passed = sum(s["passed"] for s in summaries)
    failed = sum(s["failed"] for s in summaries)
    skipped = sum(s["skipped"] for s in summaries)
    todo = sum(s["todo"] for s in summaries)
    planned_values = [s["planned"] for s in summaries]
    incomplete_values = [s["incomplete"] for s in summaries]
    planned = (
        sum(value for value in planned_values if value is not None)
        if all(value is not None for value in planned_values)
        else None
    )
    incomplete = (
        sum(value for value in incomplete_values if value is not None)
        if all(value is not None for value in incomplete_values)
        else None
    )
    missing = len(results) - len(summaries)
    note = f"; {missing} profile(s) reported no test summary" if missing else ""
    completed_text = (
        f"{completed}/{planned} tests completed"
        if planned is not None
        else f"{completed} tests completed (planned total unavailable)"
    )
    incomplete_text = (
        f"{incomplete} incomplete"
        if incomplete is not None
        else "incomplete count unavailable"
    )
    print(
        f"Total: {completed_text} across {len(summaries)} profile(s)"
        f" — {passed} passed, {failed} failed, {skipped} skipped, {todo} TODO, "
        f"{incomplete_text}{note}"
    )


def _execute_matrix(
    selected: list[tuple[str, dict[str, dict[str, Any]]]],
    workload: str,
    ordinary_tier: str,
    matrix_jobs: int,
    extra_args: list[str],
    context: RunnerContext,
    envs: dict[str, Any],
    logs_dir: Path,
) -> int:
    """Execute a validated matrix selection using ``logs_dir`` for spooling."""
    invocation_token = uuid.uuid4().hex[:10]
    cancel_event = threading.Event()
    registry = ProcessRegistry(cancel_event)
    results: dict[str, list[ProfileResult]] = {}
    workers = min(matrix_jobs, len(selected))
    # With a single worker (one platform, or serial multi-platform) there is no
    # interleaving risk, so stream each profile's output live instead of
    # buffering it until the end. This is the common CI case (one platform per
    # job) and restores live progress there.
    stream_mode = workers == 1
    futures: dict[str, Future[list[ProfileResult]]] = {}
    executor = ThreadPoolExecutor(max_workers=workers)
    interrupted = False
    try:
        for platform, profiles in selected:
            futures[platform] = executor.submit(
                _run_platform,
                platform,
                profiles,
                workload,
                ordinary_tier,
                extra_args,
                invocation_token,
                context,
                envs,
                logs_dir,
                cancel_event,
                registry,
                stream_mode,
            )
        pending = set(futures.values())
        while pending:
            _done, pending = wait(pending, timeout=0.1)
        for platform, _profiles in selected:
            try:
                results[platform] = futures[platform].result()
            except (Exception, SystemExit) as exc:  # noqa: BLE001, PERF203
                results[platform] = [
                    ProfileResult(
                        platform,
                        profile_name,
                        _profiles[profile_name]["env"],
                        1,
                        logs_dir / f"{platform}--{profile_name}.log",
                    )
                    for profile_name in _profiles_for(workload)
                ]
                for result in results[platform]:
                    result.log_path.write_text(
                        f"Platform worker failed: {exc}\n", encoding="utf-8"
                    )
    except KeyboardInterrupt:
        interrupted = True
        _cancel_executor(executor, futures, cancel_event, registry)
        for platform, profiles in selected:
            completed = results.get(platform, [])
            future = futures[platform]
            if not completed and future.done() and not future.cancelled():
                try:
                    completed = future.result()
                except (Exception, SystemExit):  # noqa: BLE001 - cancellation summary
                    completed = []
            completed = [
                result
                if result.returncode == 0
                else ProfileResult(
                    result.platform,
                    result.profile,
                    result.env_name,
                    130,
                    result.log_path,
                    streamed=result.streamed,
                )
                for result in completed
            ]
            present = {result.profile for result in completed}
            for profile_name in _profiles_for(workload):
                if profile_name in present:
                    continue
                log_path = logs_dir / f"{platform}--{profile_name}.log"
                with log_path.open("a", encoding="utf-8") as output:
                    output.write("Matrix invocation cancelled by interrupt.\n")
                completed.append(
                    ProfileResult(
                        platform,
                        profile_name,
                        profiles[profile_name]["env"],
                        130,
                        log_path,
                    )
                )
            results[platform] = completed
    except BaseException:
        interrupted = True
        _cancel_executor(executor, futures, cancel_event, registry)
        raise
    finally:
        if not interrupted:
            executor.shutdown(wait=True)

    ordered_results = [
        result for platform, _profiles in selected for result in results[platform]
    ]
    # Streamed profiles already printed live; only replay the ones that were
    # buffered (multi-platform runs, and synthesized failure/cancel results).
    to_replay = [
        result
        for result in ordered_results
        if not result.streamed and result.log_path.is_file()
    ]
    if to_replay:
        print("\n══ Buffered profile output ══")
        for result in to_replay:
            print(f"\n══ {result.platform}/{result.profile} [{result.env_name}] ══")
            _replay_log(result.log_path)

    failed = sum(result.returncode != 0 for result in ordered_results)
    print("\nMatrix results:")
    for result in ordered_results:
        if result.returncode == 0:
            state = "PASS"
        elif result.returncode == 130:
            state = "CANCELLED (130)"
        else:
            state = f"FAIL ({result.returncode})"
        print(f"  {result.platform}/{result.profile}: {state}")
    print(f"Matrix: {len(ordered_results) - failed} passed, {failed} failed")
    _print_test_total(ordered_results)
    if interrupted:
        return 130
    return 0 if failed == 0 else 1


def run(
    target_platform: str | None,
    workload: str,
    ordinary_tier: str,
    matrix_jobs: int,
    extra_args: list[str],
) -> int:
    """Run selected logical platforms; return an aggregate exit code."""
    option_error = _validate_options(workload, ordinary_tier, matrix_jobs, extra_args)
    if option_error:
        print(f"⛔ {option_error}", file=sys.stderr)
        return 2

    cfg = load_config()
    envs = load_envs(cfg.absolute_path("path.test_environments"))
    try:
        platforms = load_and_validate(
            cfg.absolute_path("path.test_lib_scenarios"), envs
        )
    except LibScenarioError as exc:
        print(f"⛔ {exc}", file=sys.stderr)
        return 2

    if target_platform is not None:
        if target_platform not in platforms:
            print(
                f"⛔ Unknown library-test platform: {target_platform!r}",
                file=sys.stderr,
            )
            return 2
        selected = [(target_platform, platforms[target_platform])]
    else:
        selected = list(platforms.items())

    context, context_error = _runner_context()
    if context is None:
        print(
            f"⛔ {context_error or 'Failed to resolve runner context.'}",
            file=sys.stderr,
        )
        return 2 if context_error else 1

    logs_dir = Path(tempfile.mkdtemp(prefix="devfeats-lib-matrix-"))
    try:
        return _execute_matrix(
            selected,
            workload,
            ordinary_tier,
            matrix_jobs,
            extra_args,
            context,
            envs,
            logs_dir,
        )
    finally:
        shutil.rmtree(logs_dir, ignore_errors=True)
