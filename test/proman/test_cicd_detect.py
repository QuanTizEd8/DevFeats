"""Tests for proman.cicd.detect — glob matching, matrix helpers, and parse utilities."""

from pathlib import Path

import proman.cicd.detect as CD

# ── any_match ─────────────────────────────────────────────────────────────────


def test_recursive_double_star_matches_nested_paths():
    changed = [
        "lib/foo/bar.baz",
        "test/unit/subsuite/example.bats",
        ".devcontainer/.dev/nested/config.json",
    ]
    assert CD.any_match(changed, ["lib/**"])
    assert CD.any_match(changed, ["test/unit/**"])
    assert CD.any_match(changed, [".devcontainer/.dev/**"])


def test_no_pattern_match_returns_false():
    changed = ["docs/source/index.md", "README.md"]
    assert not CD.any_match(changed, ["lib/**", "test/unit/**"])


# ── _bool_inp ─────────────────────────────────────────────────────────────────


def test_bool_inp_true():
    assert CD._bool_inp("true") is True


def test_bool_inp_false():
    assert CD._bool_inp("false") is False


def test_bool_inp_empty_default_true():
    assert CD._bool_inp("") is True


def test_bool_inp_empty_default_false():
    assert CD._bool_inp("", default=False) is False


# ── _parse_feature_list ───────────────────────────────────────────────────────


def test_parse_feature_list_json_array():
    assert CD._parse_feature_list('["a", "b", "c"]') == ["a", "b", "c"]


def test_parse_feature_list_comma_sep():
    assert CD._parse_feature_list("a, b, c") == ["a", "b", "c"]


def test_parse_feature_list_comma_sep_filters_empty():
    assert CD._parse_feature_list("a,,b") == ["a", "b"]


# ── helpers ───────────────────────────────────────────────────────────────────


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


# ── compute_macos_matrix ──────────────────────────────────────────────────────


def test_compute_macos_matrix_from_scenarios_yaml(tmp_path, monkeypatch):
    monkeypatch.setattr(CD, "git_repo_root", lambda: tmp_path)
    _write(tmp_path / "test/environments.yaml", """\
macos-latest:
  image: macos-latest
ubuntu-latest:
  image: ubuntu-latest
""")
    _write(tmp_path / "test/features/install-foo/scenarios.yaml", """\
default:
  envs: [ubuntu-latest]
  tests: [default.sh]
macos_default:
  envs: [macos-latest]
  tests: [macos_default.sh]
""")
    _write(tmp_path / "test/features/install-bar/scenarios.yaml", """\
linux_only:
  envs: [ubuntu-latest]
  tests: [linux_only.sh]
""")
    result = CD.compute_macos_matrix(["install-bar", "install-foo"])
    assert result == [{"feature": "install-foo", "runner": "macos-latest"}]


def test_compute_macos_matrix_empty_when_no_macos(tmp_path, monkeypatch):
    monkeypatch.setattr(CD, "git_repo_root", lambda: tmp_path)
    _write(tmp_path / "test/environments.yaml", "ubuntu-latest:\n  image: ubuntu-latest\n")
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        "default:\n  envs: [ubuntu-latest]\n  tests: [default.sh]\n",
    )
    result = CD.compute_macos_matrix(["install-foo"])
    assert result == []


def test_compute_macos_matrix_deduplicates(tmp_path, monkeypatch):
    monkeypatch.setattr(CD, "git_repo_root", lambda: tmp_path)
    _write(tmp_path / "test/environments.yaml", "macos-latest:\n  image: macos-latest\n")
    _write(tmp_path / "test/features/install-foo/scenarios.yaml", """\
scenario_a:
  envs: [macos-latest]
  tests: [a.sh]
scenario_b:
  envs: [macos-latest]
  tests: [b.sh]
""")
    result = CD.compute_macos_matrix(["install-foo"])
    assert result == [{"feature": "install-foo", "runner": "macos-latest"}]


# ── compute_unit_env_matrix ───────────────────────────────────────────────────


def test_compute_unit_env_matrix(tmp_path, monkeypatch):
    monkeypatch.setattr(CD, "git_repo_root", lambda: tmp_path)
    _write(tmp_path / "test/lib/scenarios.yaml", """\
defaults:
  options:
    log_level: trace
ubuntu-24.04:
  env: ubuntu-latest
debian-bookworm:
  env: debian-latest
""")
    result = CD.compute_unit_env_matrix()
    assert result == [
        {"name": "ubuntu-24.04", "env": "ubuntu-latest"},
        {"name": "debian-bookworm", "env": "debian-latest"},
    ]


# ── compute_unit_macos_matrix ─────────────────────────────────────────────────


def test_compute_unit_macos_matrix(tmp_path, monkeypatch):
    monkeypatch.setattr(CD, "git_repo_root", lambda: tmp_path)
    _write(tmp_path / "test/environments.yaml", """\
ubuntu-latest:
  image: ubuntu-latest
macos-latest:
  image: macos-latest
debian-latest:
  image: debian-latest
""")
    result = CD.compute_unit_macos_matrix()
    assert result == [{"runner": "macos-latest"}]


def test_compute_unit_macos_matrix_empty_when_no_macos(tmp_path, monkeypatch):
    monkeypatch.setattr(CD, "git_repo_root", lambda: tmp_path)
    _write(tmp_path / "test/environments.yaml", "ubuntu-latest:\n  image: ubuntu-latest\n")
    result = CD.compute_unit_macos_matrix()
    assert result == []
