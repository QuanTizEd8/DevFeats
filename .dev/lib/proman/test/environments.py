"""Build and resolve Docker environments for devcontainer tests."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

from proman.config import load as load_config

_DOCKER_GITHUB_ARG_LINES = "ARG GITHUB_TOKEN\nENV GITHUB_TOKEN=${GITHUB_TOKEN}\n"


def load(path: Path | str) -> dict:
    """Load an environments YAML file and return its contents as a dict."""
    with Path(path).open() as f:
        return yaml.safe_load(f) or {}


def is_macos(env_name: str, envs: dict) -> bool:
    """Return True if the named environment uses a macOS runner image."""
    env = envs.get(env_name, {})
    image = env.get("image", "")
    return bool(re.match(r"^macos", image))


def _collect_layers(
    env_name: str,
    envs: dict,
    envs_dir: Path,
    child_args: dict | None = None,
) -> tuple[str, str, dict]:
    """Flatten the from: chain into (base_image, dockerfile_body, build_args).

    base_image: root ancestor's image field.
    dockerfile_body: everything after the FROM line (excluding the GITHUB_TOKEN lines).
    build_args: all {KEY: VALUE} pairs from args: fields in the chain, to pass as
                --build-arg (standalone) or build.args (devcontainer).

    child_args: {KEY: VALUE} dict passed by the immediate child env via args:.
    """
    env = envs[env_name]
    from_env = env.get("from")
    image = env.get("image")
    build = env.get("build", {})
    df_inline = build.get("dockerfile")
    df_path = build.get("dockerfilePath")
    env_vars = env.get("env_vars", {})
    my_args = env.get("args", {})  # args THIS level passes UP to its parent

    if from_env:
        base_image, body, build_args = _collect_layers(
            from_env,
            envs,
            envs_dir,
            child_args=my_args,
        )
    else:
        base_image, body, build_args = image, "", {}

    # Merge what our child gave us into the accumulated build_args
    if child_args:
        build_args = {**build_args, **child_args}

    # ARG lines for child_args — inserted before this layer's RUN block
    arg_lines = "".join(f"ARG {k}\n" for k in (child_args or {}))

    if df_path:
        raw = (envs_dir / df_path).read_text()
        body += arg_lines
        for line in raw.splitlines(keepends=True):
            upper = line.upper().lstrip()
            if upper.startswith(("FROM ", "ARG GITHUB_TOKEN", "ENV GITHUB_TOKEN")):
                continue
            body += line
    elif df_inline:
        commands = df_inline.strip()
        body += f"{arg_lines}RUN <<'EOF'\nset -eux\n{commands}\nEOF\n"

    if env_vars:
        body += "".join(f"ENV {k}={v}\n" for k, v in env_vars.items())

    return base_image, body, build_args


def resolve(
    env_name: str,
    envs: dict,
    scenario_args: dict | None = None,
    scenario_env_vars: dict | None = None,
) -> str:
    """Resolve an environment name to a Docker image tag, building if needed."""
    env = envs.get(env_name)
    if env is None:
        print(f"⛔ Unknown environment: {env_name!r}", file=sys.stderr)
        sys.exit(1)

    if is_macos(env_name, envs):
        return env["image"]

    envs_dir = load_config().absolute_path("path.test_envs")
    base_image, body, build_args = _collect_layers(
        env_name,
        envs,
        envs_dir,
        child_args=scenario_args or None,
    )

    if scenario_env_vars:
        body += "".join(f"ENV {k}={v}\n" for k, v in scenario_env_vars.items())

    if not body and not build_args:
        return base_image  # fast path: nothing to build

    safe_name = re.sub(r"[^a-zA-Z0-9_.\-]", "-", env_name)
    if scenario_args or scenario_env_vars:
        h = hashlib.sha256(
            json.dumps(
                {"a": scenario_args or {}, "e": scenario_env_vars or {}},
                sort_keys=True,
            ).encode(),
        ).hexdigest()[:8]
        tag = f"devfeats-env-{safe_name}-{h}:latest"
    else:
        tag = f"devfeats-env-{safe_name}:latest"

    envs_dir.mkdir(parents=True, exist_ok=True)
    dockerfile_content = f"FROM {base_image}\n{_DOCKER_GITHUB_ARG_LINES}{body}"

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".Dockerfile",
        dir=envs_dir,
        delete=False,
    ) as tf:
        tf.write(dockerfile_content)
        df_tmp = tf.name

    try:
        cmd = ["docker", "build", "-t", tag, "-f", df_tmp, str(envs_dir)]
        for k, v in build_args.items():
            cmd.extend(["--build-arg", f"{k}={v}"])
        env_build = {**os.environ, "DOCKER_BUILDKIT": "1"}
        subprocess.run(cmd, check=True, env=env_build)
    finally:
        Path(df_tmp).unlink(missing_ok=True)

    return tag


def resolve_cli() -> None:
    """Parse CLI arguments and print the resolved Docker image tag."""
    env_name: str | None = None
    scenario_args: dict = {}
    scenario_env_vars: dict = {}

    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg in ("--arg", "--env-var"):
            if i + 1 >= len(sys.argv):
                print(
                    "usage: proman-test-resolve-env <env-name>"
                    " [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]",
                    file=sys.stderr,
                )
                sys.exit(1)
            k, _, v = sys.argv[i + 1].partition("=")
            if arg == "--arg":
                scenario_args[k] = v
            else:
                scenario_env_vars[k] = v
            i += 2
        elif not arg.startswith("--") and env_name is None:
            env_name = arg
            i += 1
        else:
            print(
                "usage: proman-test-resolve-env <env-name>"
                " [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]",
                file=sys.stderr,
            )
            sys.exit(1)

    if env_name is None:
        print(
            "usage: proman-test-resolve-env <env-name>"
            " [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]",
            file=sys.stderr,
        )
        sys.exit(1)

    envs = load(load_config().absolute_path("path.test_environments"))
    print(
        resolve(
            env_name,
            envs,
            scenario_args=scenario_args or None,
            scenario_env_vars=scenario_env_vars or None,
        ),
    )
