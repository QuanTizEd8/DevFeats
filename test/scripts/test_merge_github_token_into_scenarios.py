"""Unit tests for merge_github_token_into_scenarios."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SCRIPT_PATH = REPO_ROOT / "test" / "scripts" / "merge_github_token_into_scenarios.py"


def _load_module():
    spec = importlib.util.spec_from_file_location(
        "merge_github_token_into_scenarios", SCRIPT_PATH
    )
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("merge_github_token_into_scenarios", mod)
    spec.loader.exec_module(mod)
    return mod


m = _load_module()
TOKEN_REF = m.TOKEN_REF


class TestMergeScenario(unittest.TestCase):
    def test_adds_build_when_image_only(self) -> None:
        scenario = {
            "image": "ubuntu:latest",
            "features": {"install-x": {}},
        }
        self.assertTrue(m.merge_github_token_into_scenario(scenario))
        self.assertEqual(
            scenario["build"]["args"]["GITHUB_TOKEN"],
            TOKEN_REF,
        )

    def test_merges_into_existing_build_without_args(self) -> None:
        scenario = {"build": {"dockerfile": "Dockerfile"}, "features": {}}
        self.assertTrue(m.merge_github_token_into_scenario(scenario))
        self.assertEqual(scenario["build"]["dockerfile"], "Dockerfile")
        self.assertEqual(scenario["build"]["args"]["GITHUB_TOKEN"], TOKEN_REF)

    def test_merges_into_existing_args(self) -> None:
        scenario = {
            "build": {"dockerfile": "Dockerfile", "args": {"FOO": "bar"}},
            "features": {},
        }
        self.assertTrue(m.merge_github_token_into_scenario(scenario))
        self.assertEqual(scenario["build"]["args"]["FOO"], "bar")
        self.assertEqual(scenario["build"]["args"]["GITHUB_TOKEN"], TOKEN_REF)

    def test_preserves_explicit_github_token(self) -> None:
        scenario = {
            "build": {
                "args": {"GITHUB_TOKEN": "${localEnv:GH_TOKEN_OVERRIDE}"},
            }
        }
        self.assertFalse(m.merge_github_token_into_scenario(scenario))
        self.assertEqual(
            scenario["build"]["args"]["GITHUB_TOKEN"],
            "${localEnv:GH_TOKEN_OVERRIDE}",
        )

    def test_idempotent_second_call(self) -> None:
        scenario = {"image": "ubuntu:latest", "features": {}}
        self.assertTrue(m.merge_github_token_into_scenario(scenario))
        self.assertFalse(m.merge_github_token_into_scenario(scenario))


class TestMergeFile(unittest.TestCase):
    def test_writes_merged_json(self) -> None:
        payload = {
            "only_image": {
                "image": "ubuntu:latest",
                "features": {"f": {}},
            }
        }
        with tempfile.TemporaryDirectory() as tmp:
            p = pathlib.Path(tmp) / "scenarios.json"
            p.write_text(json.dumps(payload), encoding="utf-8")
            self.assertTrue(m.merge_file(p))
            out = json.loads(p.read_text(encoding="utf-8"))
            self.assertEqual(
                out["only_image"]["build"]["args"]["GITHUB_TOKEN"],
                TOKEN_REF,
            )


if __name__ == "__main__":
    unittest.main()
