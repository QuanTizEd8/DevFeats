"""Run devcontainer feature tests in devcontainer, standalone, and macOS modes."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from proman.const import activation_profile_d, export_profile_d, feat_share_dir
from proman.git import git_owner_repo

from .checks import install_failure_patterns, load_checks
from .codegen import generate_tests
from .environments import is_macos, resolve
from .environments import load as load_envs
from .gen_devcontainer import generate
from .scenarios import expand_envs, merge_defaults
from .scenarios import load as load_scenarios

_SHIM_SETUP = (
    "mkdir -p /tmp/_testlib"
    " && cp /repo/test/support/assert.sh /tmp/_testlib/dev-container-features-test-lib"
    " && chmod +x /tmp/_testlib/dev-container-features-test-lib"
)

_SUDO_STUB = (
    "mkdir -p /tmp/_nosudo"
    r" && printf '#!/bin/sh\nexit 1\n' > /tmp/_nosudo/sudo"
    " && chmod +x /tmp/_nosudo/sudo"
    " && export PATH=/tmp/_nosudo:$PATH"
)

_MACOS_CLEAN_BASE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

_MACOS_ENV_PASSTHROUGH = frozenset(
    {
        "HOME",
        "USER",
        "LOGNAME",
        "SHELL",
        "TERM",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "LC_MESSAGES",
        "LC_NUMERIC",
        "LC_TIME",
        "CI",
        "GITHUB_TOKEN",
        "GITHUB_WORKSPACE",
        "XPC_FLAGS",
        "XPC_SERVICE_NAME",
    },
)


def _standalone_install_block(
    feature: str,
    scenario_key: str,
    *,
    expect_install_failure: bool,
    failure_patterns: list[str],
) -> str:
    """Shell fragment: run install once, capture output, validate exit and messages."""
    lines = [
        '_FEATURE_INSTALL_LOG="$(mktemp)"',
        f'sh /repo/src/{feature}/install.sh >"${{_FEATURE_INSTALL_LOG}}" 2>&1',
        "FEATURE_INSTALL_RC=$?",
    ]
    if expect_install_failure:
        lines.append(
            'if [ "${FEATURE_INSTALL_RC}" -eq 0 ]; then '
            f'echo "⛔ standalone scenario {scenario_key}: install unexpectedly succeeded '
            '(expect_install_failure=true)." >&2; '
            'echo "--- install output ---" >&2; cat "${_FEATURE_INSTALL_LOG}" >&2; exit 1; fi'
        )
        for pattern in failure_patterns:
            qpat = shlex.quote(pattern)
            lines.append(
                f'if ! grep -Fq {qpat} "${{_FEATURE_INSTALL_LOG}}"; then '
                f'echo "⛔ standalone scenario {scenario_key}: install output missing '
                f"expected message: {pattern!r}" >&2; '
                'echo "--- install output ---" >&2; cat "${_FEATURE_INSTALL_LOG}" >&2; exit 1; fi'
            )
    else:
        lines.append(
            'if [ "${FEATURE_INSTALL_RC}" -ne 0 ]; then '
            f'echo "⛔ standalone scenario {scenario_key}: install failed with exit code '
            '${FEATURE_INSTALL_RC}." >&2; '
            'echo "--- install output ---" >&2; cat "${_FEATURE_INSTALL_LOG}" >&2; '
            "exit ${FEATURE_INSTALL_RC}; fi"
        )
    lines.append('rm -f "${_FEATURE_INSTALL_LOG}"')
    return "\n".join(lines)


def _validate_install_failure_output(
    scenario_key: str,
    *,
    returncode: int,
    output: str,
    failure_patterns: list[str],
) -> str | None:
    """Return an error message when an expected install failure is not satisfied."""
    if returncode == 0:
        return (
            f"macos scenario {scenario_key}: install unexpectedly succeeded "
            "(expect_install_failure=true)."
        )
    for pattern in failure_patterns:
        if pattern not in output:
            return (
                f"macos scenario {scenario_key}: install output missing expected "
                f"message: {pattern!r}"
            )
    return None


def _options_exports(options: dict) -> str:
    lines = []
    for k, v in options.items():
        env_key = k.upper().replace("-", "_")
        val = str(v).lower() if isinstance(v, bool) else str(v)
        lines.append(f"export {env_key}={shlex.quote(val)}")
    return "\n".join(lines)


def _build_macos_base_env(env_name: str, envs: dict, repo_root: Path) -> dict:
    """Return the env dict used for all macOS subprocess calls in a scenario.

    When clean_path is set on the environment, starts from an allowlist of
    essential variables and replaces PATH with the macOS system baseline plus
    any path_prepend directories declared on the environment. Otherwise returns
    a copy of os.environ (unchanged behaviour for environments without clean_path).
    """
    env_def = envs.get(env_name, {})
    if not env_def.get("clean_path", False):
        base = dict(os.environ)
        base["REPO_ROOT"] = str(repo_root)
        return base
    base = {k: v for k, v in os.environ.items() if k in _MACOS_ENV_PASSTHROUGH}
    prepend = env_def.get("path_prepend", "").strip()
    clean_base = _MACOS_CLEAN_BASE_PATH
    base["PATH"] = f"{prepend}:{clean_base}" if prepend else clean_base
    base["REPO_ROOT"] = str(repo_root)
    return base


def _load_entries(feature: str, repo_root: Path, envs: dict) -> list[dict]:
    scenarios_path = repo_root / "test" / "features" / feature / "scenarios.yaml"
    defaults, scenarios = load_scenarios(scenarios_path)
    entries = []
    for name, sc in scenarios.items():
        merged_sc = merge_defaults(sc, defaults)
        for key, env_name, scenario in expand_envs(name, merged_sc):
            entries.append(
                {
                    "key": key,
                    "env_name": env_name,
                    "env_is_macos": is_macos(env_name, envs),
                    "scenario": scenario,
                },
            )
    return entries


def _run_devcontainer(
    feature: str,
    repo_root: Path,
    filter_prefix: str,
) -> bool:
    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)
        (tmpdir / "src").symlink_to(repo_root / "src")

        test_out_dir = tmpdir / "test" / feature
        generate(
            feature=feature,
            scenarios_path=repo_root / "test" / "features" / feature / "scenarios.yaml",
            envs_path=repo_root / "test" / "environments.yaml",
            out_dir=tmpdir,
        )

        if filter_prefix:
            scenarios_json_path = test_out_dir / "scenarios.json"
            with scenarios_json_path.open() as f:
                all_scenarios = json.load(f)
            filtered = {
                k: v for k, v in all_scenarios.items() if k.startswith(filter_prefix)
            }
            with scenarios_json_path.open("w") as f:
                json.dump(filtered, f, indent=4)
                f.write("\n")

        result = subprocess.run(
            [
                "devcontainer",
                "features",
                "test",
                "--skip-autogenerated",
                "-f",
                feature,
                "--project-folder",
                str(tmpdir),
            ],
            check=False,
        )
        return result.returncode == 0


def _run_standalone(
    feature: str,
    repo_root: Path,
    entries: list[dict],
    filter_prefix: str,
    envs: dict,
) -> bool:
    checks_path = repo_root / "test" / "features" / feature / "checks.yaml"
    checks_data = load_checks(checks_path) if checks_path.exists() else {}

    success = True
    for entry in entries:
        key = entry["key"]
        env_name = entry["env_name"]
        scenario = entry["scenario"]

        if entry["env_is_macos"]:
            continue
        if filter_prefix and not key.startswith(filter_prefix):
            continue

        modes = scenario.get("modes", ["devcontainer", "standalone"])
        if "standalone" not in modes:
            continue

        standalone_cfg = scenario.get("standalone", {})
        user = standalone_cfg.get("user", "")
        sudo_ok = standalone_cfg.get("sudo", True)
        network = standalone_cfg.get("network", "")
        skip_install = standalone_cfg.get("skip_install", False)
        expect_install_failure = bool(scenario.get("expect_install_failure", False))
        test_scripts = scenario.get("tests", [])
        failure_patterns = install_failure_patterns(checks_data, test_scripts)
        if expect_install_failure and not failure_patterns:
            print(
                f"⛔ standalone scenario {key}: expect_install_failure=true but no "
                "install_failure pattern in checks.yaml for tests "
                f"{test_scripts!r}.",
                file=sys.stderr,
            )
            success = False
            continue
        options = scenario.get("options", {})
        sc_args = scenario.get("args") or {}
        sc_env_vars = scenario.get("env_vars") or {}

        image = resolve(
            env_name,
            envs,
            repo_root,
            scenario_args=sc_args or None,
            scenario_env_vars=sc_env_vars or None,
        )

        test_cmd_lines = []
        _owner, _repo = git_owner_repo()
        _feat_share = feat_share_dir(feature, _owner, _repo)
        _export_pd = export_profile_d(feature, _owner, _repo)
        _activation_pd = activation_profile_d(feature, _owner, _repo)
        for ts in test_scripts:
            ts_name = ts if ts.endswith(".sh") else f"{ts}.sh"
            ts_path = f"/repo/test/features/{feature}/tests/{ts_name}"
            if user:
                test_cmd_lines.append(
                    f"su {user} -c '"
                    f"_FEAT_SHARE_DIR={shlex.quote(_feat_share)}"
                    f" _EXPORT_PROFILE_D={shlex.quote(_export_pd)}"
                    f" _ACTIVATION_PROFILE_D={shlex.quote(_activation_pd)}"
                    f" PATH=/tmp/_testlib:$PATH"
                    f" REPO_ROOT=/repo FEATURE_INSTALL_RC=$FEATURE_INSTALL_RC"
                    f" bash {ts_path}'",
                )
            else:
                test_cmd_lines.append(
                    f"_FEAT_SHARE_DIR={shlex.quote(_feat_share)}"
                    f" _EXPORT_PROFILE_D={shlex.quote(_export_pd)}"
                    f" _ACTIVATION_PROFILE_D={shlex.quote(_activation_pd)}"
                    f" PATH=/tmp/_testlib:$PATH REPO_ROOT=/repo"
                    f" FEATURE_INSTALL_RC=$FEATURE_INSTALL_RC bash {ts_path}",
                )

        parts = [
            _SHIM_SETUP,
            scenario.get("setup", ""),
            _SUDO_STUB if not sudo_ok else "",
            _options_exports(options),
        ]
        if not skip_install:
            parts.append(
                _standalone_install_block(
                    feature,
                    key,
                    expect_install_failure=expect_install_failure,
                    failure_patterns=failure_patterns,
                ),
            )
        else:
            parts.append("FEATURE_INSTALL_RC=0")
            if expect_install_failure:
                parts.append(
                    'echo "⛔ standalone scenario ' + key + ": invalid config "
                    '(skip_install=true with expect_install_failure=true)." >&2; '
                    "exit 1",
                )
        parts.extend(test_cmd_lines)

        run_cmd = "\n".join(p for p in parts if p)

        container_name = f"standalone-{feature}-{re.sub(r'[.+]', '-', key)}"
        run_in_container = (
            repo_root / ".dev" / "scripts" / "test" / "run-in-container.sh"
        )
        container_cmd = [
            "bash",
            str(run_in_container),
            "--image",
            image,
            "--name",
            container_name,
            "--run",
            run_cmd,
        ]
        if network == "none":
            container_cmd.append("--network-none")

        print(f"\n══ standalone: {key} [{env_name}] ══", flush=True)
        result = subprocess.run(container_cmd, check=False)
        if result.returncode != 0:
            success = False

    return success


def _run_macos(
    feature: str,
    repo_root: Path,
    entries: list[dict],
    filter_prefix: str,
    envs: dict,
) -> bool:
    checks_path = repo_root / "test" / "features" / feature / "checks.yaml"
    checks_data = load_checks(checks_path) if checks_path.exists() else {}

    shim_dir = tempfile.mkdtemp()
    try:
        shim_path = Path(shim_dir) / "dev-container-features-test-lib"
        shutil.copy(repo_root / "test" / "support" / "assert.sh", shim_path)
        shim_path.chmod(0o755)

        success = True
        for entry in entries:
            if not entry["env_is_macos"]:
                continue

            key = entry["key"]
            env_name = entry["env_name"]
            scenario = entry["scenario"]

            if filter_prefix and not key.startswith(filter_prefix):
                continue

            standalone_cfg = scenario.get("standalone", {})
            user = standalone_cfg.get("user", "")
            skip_install = standalone_cfg.get("skip_install", False)
            expect_install_failure = bool(scenario.get("expect_install_failure", False))
            test_scripts = scenario.get("tests", [])
            failure_patterns = install_failure_patterns(checks_data, test_scripts)
            if expect_install_failure and not failure_patterns:
                print(
                    f"⛔ macos scenario {key}: expect_install_failure=true but no "
                    "install_failure pattern in checks.yaml for tests "
                    f"{test_scripts!r}.",
                    file=sys.stderr,
                )
                success = False
                continue
            options = scenario.get("options", {})

            # base_env: clean or full runner env, no feature options yet.
            # Mirrors Docker: env-level setup and scenario setup run before
            # feature options are exported, matching standalone mode behaviour.
            base_env = _build_macos_base_env(env_name, envs, repo_root)

            env_def = envs.get(env_name, {})
            # macOS: `build.dockerfile` is env bootstrap shell (not Docker). Linux
            # envs use it as Dockerfile RUN body via environments.resolve().
            env_build = env_def.get("build", {}).get("dockerfile", "")
            if env_build:
                subprocess.run(["bash", "-c", env_build], check=True, env=base_env)

            scenario_setup = scenario.get("setup", "")
            if scenario_setup:
                subprocess.run(["bash", "-c", scenario_setup], check=True, env=base_env)

            # run_env adds feature options on top of base_env for the install
            # script and test scripts.
            run_env = dict(base_env)
            for k, v in options.items():
                env_key = k.upper().replace("-", "_")
                run_env[env_key] = str(v).lower() if isinstance(v, bool) else str(v)

            print(f"\n══ macos: {key} ══", flush=True)

            install_rc = 0
            if not skip_install:
                install_script = repo_root / "src" / feature / "install.sh"
                install_result = subprocess.run(
                    ["/bin/sh", str(install_script)],
                    check=False,
                    env=run_env,
                    capture_output=True,
                    text=True,
                )
                install_rc = install_result.returncode
                install_output = install_result.stdout + install_result.stderr
                if expect_install_failure:
                    err = _validate_install_failure_output(
                        key,
                        returncode=install_rc,
                        output=install_output,
                        failure_patterns=failure_patterns,
                    )
                    if err:
                        print(f"⛔ {err}", file=sys.stderr)
                        if install_output:
                            print("--- install output ---", file=sys.stderr)
                            print(install_output, file=sys.stderr)
                        success = False
                elif install_rc != 0:
                    print(
                        f"⛔ macos scenario {key}: install failed with "
                        f"exit code {install_rc}.",
                        file=sys.stderr,
                    )
                    success = False
                    # Preserve previous semantics: when install unexpectedly fails,
                    # skip scenario tests because setup state is not guaranteed.
                    continue
            elif expect_install_failure:
                print(
                    f"⛔ macos scenario {key}: invalid config "
                    "(skip_install=true with expect_install_failure=true).",
                    file=sys.stderr,
                )
                success = False
                continue

            for ts in test_scripts:
                ts_name = ts if ts.endswith(".sh") else f"{ts}.sh"
                ts_path = str(
                    repo_root / "test" / "features" / feature / "tests" / ts_name,
                )
                _owner, _repo = git_owner_repo()
                test_env = {
                    **run_env,
                    "PATH": f"{shim_dir}:{run_env['PATH']}",
                    "FEATURE_INSTALL_RC": str(install_rc),
                    "_FEAT_SHARE_DIR": feat_share_dir(feature, _owner, _repo),
                    "_EXPORT_PROFILE_D": export_profile_d(feature, _owner, _repo),
                    "_ACTIVATION_PROFILE_D": activation_profile_d(
                        feature, _owner, _repo
                    ),
                }
                if user:
                    path_q = shlex.quote(test_env["PATH"])
                    root_q = shlex.quote(str(repo_root))
                    ts_q = shlex.quote(ts_path)
                    cmd = f"PATH={path_q} REPO_ROOT={root_q} bash {ts_q}"
                    result = subprocess.run(
                        ["su", user, "-c", cmd],
                        check=False,
                        env=test_env,
                    )
                else:
                    result = subprocess.run(
                        ["bash", ts_path],
                        env=test_env,
                        check=False,
                    )
                if result.returncode != 0:
                    success = False

        return success
    finally:
        shutil.rmtree(shim_dir)


def main() -> None:
    """Entry point for proman-test-run CLI."""
    parser = argparse.ArgumentParser(
        description="Run devcontainer feature tests (devcontainer, standalone, macOS).",
    )
    parser.add_argument("feature", help="Feature name (e.g. install-pixi)")
    parser.add_argument(
        "--mode",
        default="all",
        choices=["devcontainer", "standalone", "macos", "all"],
        help="Test mode to run (default: all)",
    )
    parser.add_argument(
        "--filter",
        default="",
        metavar="PREFIX",
        help="Only run scenarios whose key starts with PREFIX",
    )
    args = parser.parse_args()

    repo_root_str = (
        os.environ.get("REPO_ROOT")
        or subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
        ).strip()
    )
    repo_root = Path(repo_root_str)
    os.environ.setdefault("REPO_ROOT", str(repo_root))

    tests_dir = repo_root / "test" / "features" / args.feature / "tests"
    checks_path = repo_root / "test" / "features" / args.feature / "checks.yaml"
    if checks_path.exists():
        generate_tests(args.feature, checks_path, tests_dir)

    if not tests_dir.is_dir():
        print(
            f"⛔ tests/ directory not found for feature {args.feature}: {tests_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    envs_path = repo_root / "test" / "environments.yaml"
    envs = load_envs(envs_path)
    entries = _load_entries(args.feature, repo_root, envs)

    filter_prefix: str = args.filter

    if args.mode == "devcontainer":
        ok = _run_devcontainer(args.feature, repo_root, filter_prefix)
        sys.exit(0 if ok else 1)

    if args.mode == "standalone":
        ok = _run_standalone(args.feature, repo_root, entries, filter_prefix, envs)
        sys.exit(0 if ok else 1)

    if args.mode == "macos":
        ok = _run_macos(args.feature, repo_root, entries, filter_prefix, envs)
        sys.exit(0 if ok else 1)

    rc = 0
    if not _run_devcontainer(args.feature, repo_root, filter_prefix):
        rc = 1
    if not _run_standalone(args.feature, repo_root, entries, filter_prefix, envs):
        rc = 1
    has_macos = sys.platform == "darwin" or any(e["env_is_macos"] for e in entries)
    if has_macos and not _run_macos(
        args.feature,
        repo_root,
        entries,
        filter_prefix,
        envs,
    ):
        rc = 1
    sys.exit(rc)
