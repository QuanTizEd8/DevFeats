"""Tests for merge_github_token_into_scenarios."""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile

REPO_ROOT = pathlib.Path(
    subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
)
SCRIPT_PATH = REPO_ROOT / ".dev" / "scripts" / "test" / "merge_github_token_into_scenarios.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("merge_github_token_into_scenarios", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("merge_github_token_into_scenarios", mod)
    spec.loader.exec_module(mod)
    return mod


m = _load_module()
TOKEN_REF = m.TOKEN_REF


def test_adds_build_when_image_only():
    scenario = {"image": "ubuntu:latest", "features": {"install-x": {}}}
    assert m.merge_github_token_into_scenario(scenario)
    assert scenario["build"]["args"]["GITHUB_TOKEN"] == TOKEN_REF


def test_merges_into_existing_build_without_args():
    scenario = {"build": {"dockerfile": "Dockerfile"}, "features": {}}
    assert m.merge_github_token_into_scenario(scenario)
    assert scenario["build"]["dockerfile"] == "Dockerfile"
    assert scenario["build"]["args"]["GITHUB_TOKEN"] == TOKEN_REF


def test_merges_into_existing_args():
    scenario = {
        "build": {"dockerfile": "Dockerfile", "args": {"FOO": "bar"}},
        "features": {},
    }
    assert m.merge_github_token_into_scenario(scenario)
    assert scenario["build"]["args"]["FOO"] == "bar"
    assert scenario["build"]["args"]["GITHUB_TOKEN"] == TOKEN_REF


def test_preserves_explicit_github_token():
    scenario = {"build": {"args": {"GITHUB_TOKEN": "${localEnv:GH_TOKEN_OVERRIDE}"}}}
    assert not m.merge_github_token_into_scenario(scenario)
    assert scenario["build"]["args"]["GITHUB_TOKEN"] == "${localEnv:GH_TOKEN_OVERRIDE}"


def test_idempotent_second_call():
    scenario = {"image": "ubuntu:latest", "features": {}}
    assert m.merge_github_token_into_scenario(scenario)
    assert not m.merge_github_token_into_scenario(scenario)


def test_writes_merged_json():
    payload = {"only_image": {"image": "ubuntu:latest", "features": {"f": {}}}}
    with tempfile.TemporaryDirectory() as tmp:
        p = pathlib.Path(tmp) / "scenarios.json"
        p.write_text(json.dumps(payload), encoding="utf-8")
        assert m.merge_file(p)
        out = json.loads(p.read_text(encoding="utf-8"))
        assert out["only_image"]["build"]["args"]["GITHUB_TOKEN"] == TOKEN_REF
