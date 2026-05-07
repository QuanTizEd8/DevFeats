from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .environments import _TOKEN_LINES, _collect_layers, is_macos
from .environments import load as load_envs
from .scenarios import expand_envs, merge_defaults
from .scenarios import load as load_scenarios


def _inject_github_token(scenarios: dict) -> None:
    for scenario in scenarios.values():
        if not isinstance(scenario, dict):
            continue
        build = scenario.get("build")
        if build is None:
            scenario["build"] = {"args": {"GITHUB_TOKEN": "${localEnv:GITHUB_TOKEN}"}}
        elif isinstance(build, dict):
            args = build.setdefault("args", {})
            if isinstance(args, dict):
                args.setdefault("GITHUB_TOKEN", "${localEnv:GITHUB_TOKEN}")


def _build_scenario(
    key: str,
    env_name: str,
    scenario: dict,
    feature: str,
    envs: dict,
    out_dir: Path,
    envs_dir: Path,
) -> dict:
    sc_args = scenario.get("args") or {}
    sc_env_vars = scenario.get("env_vars") or {}

    base_image, body, build_args = _collect_layers(
        env_name,
        envs,
        envs_dir,
        child_args=sc_args or None,
    )

    if sc_env_vars:
        body += "".join(f"ENV {k}={v}\n" for k, v in sc_env_vars.items())

    setup = scenario.get("setup", "").strip()
    if setup:
        body += f"RUN <<'EOF'\nset -eux\n{setup}\nEOF\n"

    df_name = f"{key}.Dockerfile"
    (out_dir / df_name).write_text(f"FROM {base_image}\n{_TOKEN_LINES}{body}")
    result: dict = {"build": {"dockerfile": df_name}}
    if build_args:
        result["build"]["args"] = dict(build_args)

    dc = scenario.get("devcontainer", {})
    if dc.get("remoteUser"):
        result["remoteUser"] = dc["remoteUser"]
    if dc.get("containerUser"):
        result["containerUser"] = dc["containerUser"]
    if dc.get("build", {}).get("args"):
        result.setdefault("build", {}).setdefault("args", {}).update(
            dc["build"]["args"],
        )

    options = scenario.get("options", {})
    result["features"] = {feature: options}
    result["testFiles"] = scenario.get("tests", [])

    return result


def generate(
    feature: str,
    scenarios_path: Path | str,
    envs_path: Path | str,
    out_dir: Path | str,
) -> None:
    scenarios_path = Path(scenarios_path)
    envs_path = Path(envs_path)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    defaults, scenarios = load_scenarios(scenarios_path)
    envs = load_envs(envs_path)
    envs_dir = envs_path.parent / "envs"

    scenarios_dir = out_dir / "test" / feature
    scenarios_dir.mkdir(parents=True, exist_ok=True)

    output: dict = {}
    for name, sc in scenarios.items():
        sc = merge_defaults(sc, defaults)
        modes: list[str] = sc.get("modes", ["devcontainer", "standalone"])

        for key, env_name, scenario in expand_envs(name, sc):
            if is_macos(env_name, envs):
                continue
            if modes == ["standalone"]:
                continue

            # Dockerfiles go into a per-scenario subdir so the devcontainer CLI
            # picks them up via its test/{feature}/{key}/ → .devcontainer/ copy.
            scenario_dir = scenarios_dir / key
            scenario_dir.mkdir(parents=True, exist_ok=True)

            output[key] = _build_scenario(
                key,
                env_name,
                scenario,
                feature,
                envs,
                scenario_dir,
                envs_dir,
            )

    _inject_github_token(output)
    (scenarios_dir / "scenarios.json").write_text(json.dumps(output, indent=4) + "\n")


def main_cli() -> None:
    parser = argparse.ArgumentParser(
        description="Generate devcontainer scenarios.json from unified scenarios.yaml",
    )
    parser.add_argument("--feature", required=True)
    parser.add_argument("--unified", required=True, type=Path)
    parser.add_argument("--envs", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()
    generate(args.feature, args.unified, args.envs, args.out_dir)


if __name__ == "__main__":
    sys.exit(main_cli() or 0)
