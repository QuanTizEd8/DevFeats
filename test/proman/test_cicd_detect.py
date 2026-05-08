"""Tests for proman.cicd.detect — glob matching, matrix helpers, and parse utilities."""

from pathlib import Path

import proman.cicd.detect as cd
import pytest

# ── any_match ─────────────────────────────────────────────────────────────────


def test_recursive_double_star_matches_nested_paths() -> None:
    """Verify ** patterns match files nested at any depth."""
    changed = [
        "lib/foo/bar.baz",
        "test/unit/subsuite/example.bats",
        ".devcontainer/.dev/nested/config.json",
    ]
    assert cd.any_match(changed, ["lib/**"])
    assert cd.any_match(changed, ["test/unit/**"])
    assert cd.any_match(changed, [".devcontainer/.dev/**"])


def test_no_pattern_match_returns_false() -> None:
    """Verify any_match returns False when no pattern matches."""
    changed = ["docs/source/index.md", "README.md"]
    assert not cd.any_match(changed, ["lib/**", "test/unit/**"])


# ── _bool_inp ─────────────────────────────────────────────────────────────────


def test_bool_inp_true() -> None:
    """Verify 'true' parses to True."""
    assert cd._bool_inp("true") is True


def test_bool_inp_false() -> None:
    """Verify 'false' parses to False."""
    assert cd._bool_inp("false") is False


def test_bool_inp_empty_default_true() -> None:
    """Verify empty string returns the default True."""
    assert cd._bool_inp("") is True


def test_bool_inp_empty_default_false() -> None:
    """Verify empty string returns the supplied default False."""
    assert cd._bool_inp("", default=False) is False


# ── _parse_feature_list ───────────────────────────────────────────────────────


def test_parse_feature_list_json_array() -> None:
    """Verify JSON array strings are parsed into a list."""
    assert cd._parse_feature_list('["a", "b", "c"]') == ["a", "b", "c"]


def test_parse_feature_list_comma_sep() -> None:
    """Verify comma-separated strings are split into a list."""
    assert cd._parse_feature_list("a, b, c") == ["a", "b", "c"]


def test_parse_feature_list_comma_sep_filters_empty() -> None:
    """Verify empty tokens from consecutive commas are filtered out."""
    assert cd._parse_feature_list("a,,b") == ["a", "b"]


# ── helpers ───────────────────────────────────────────────────────────────────


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


# ── compute_macos_matrix ──────────────────────────────────────────────────────


def test_compute_macos_matrix_from_scenarios_yaml(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify macOS matrix is built from scenarios that reference macOS envs."""
    monkeypatch.setattr(cd, "git_repo_root", lambda: tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        """\
macos-latest:
  image: macos-latest
ubuntu-latest:
  image: ubuntu-latest
""",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        """\
default:
  envs: [ubuntu-latest]
  tests: [default.sh]
macos_default:
  envs: [macos-latest]
  tests: [macos_default.sh]
""",
    )
    _write(
        tmp_path / "test/features/install-bar/scenarios.yaml",
        """\
linux_only:
  envs: [ubuntu-latest]
  tests: [linux_only.sh]
""",
    )
    result = cd.compute_macos_matrix(["install-bar", "install-foo"])
    assert result == [{"feature": "install-foo", "runner": "macos-latest"}]


def test_compute_macos_matrix_empty_when_no_macos(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify macOS matrix is empty when no scenario references a macOS env."""
    monkeypatch.setattr(cd, "git_repo_root", lambda: tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        "default:\n  envs: [ubuntu-latest]\n  tests: [default.sh]\n",
    )
    result = cd.compute_macos_matrix(["install-foo"])
    assert result == []


def test_compute_macos_matrix_deduplicates(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify each feature appears at most once in the macOS matrix."""
    monkeypatch.setattr(cd, "git_repo_root", lambda: tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "macos-latest:\n  image: macos-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        """\
scenario_a:
  envs: [macos-latest]
  tests: [a.sh]
scenario_b:
  envs: [macos-latest]
  tests: [b.sh]
""",
    )
    result = cd.compute_macos_matrix(["install-foo"])
    assert result == [{"feature": "install-foo", "runner": "macos-latest"}]


# ── compute_unit_env_matrix ───────────────────────────────────────────────────


def test_compute_unit_env_matrix(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify unit env matrix is built from scenarios.yaml entries."""
    monkeypatch.setattr(cd, "git_repo_root", lambda: tmp_path)
    _write(
        tmp_path / "test/lib/scenarios.yaml",
        """\
defaults:
  options:
    log_level: trace
ubuntu-24.04:
  env: ubuntu-latest
debian-bookworm:
  env: debian-latest
""",
    )
    result = cd.compute_unit_env_matrix()
    assert result == [
        {"name": "ubuntu-24.04", "env": "ubuntu-latest"},
        {"name": "debian-bookworm", "env": "debian-latest"},
    ]


# ── compute_unit_macos_matrix ─────────────────────────────────────────────────


def test_compute_unit_macos_matrix(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify unit macOS matrix contains only macOS runners."""
    monkeypatch.setattr(cd, "git_repo_root", lambda: tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        """\
ubuntu-latest:
  image: ubuntu-latest
macos-latest:
  image: macos-latest
debian-latest:
  image: debian-latest
""",
    )
    result = cd.compute_unit_macos_matrix()
    assert result == [{"runner": "macos-latest"}]


def test_compute_unit_macos_matrix_empty_when_no_macos(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify unit macOS matrix is empty when no macOS environments exist."""
    monkeypatch.setattr(cd, "git_repo_root", lambda: tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    result = cd.compute_unit_macos_matrix()
    assert result == []
