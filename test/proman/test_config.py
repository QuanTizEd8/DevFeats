"""Round-trip tests for proman.config loaders."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pathlib import Path

    import pytest

import proman.config as cfg


def _patch_loaders(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    project_yaml: str,
    ci_yaml: str,
) -> None:
    """Write YAML files to tmp_path and redirect loaders to read them."""
    (tmp_path / ".config").mkdir(parents=True)
    (tmp_path / ".config/project.yaml").write_text(project_yaml, encoding="utf-8")
    (tmp_path / ".config/ci.yaml").write_text(ci_yaml, encoding="utf-8")
    monkeypatch.setattr(cfg, "git_repo_root", lambda: tmp_path)
    # Clear caches so the patched root is used.
    cfg.load_project.cache_clear()
    cfg.load_ci.cache_clear()


_MINIMAL_PROJECT = "version: 1\nname: testproject\n"

_MINIMAL_CI = """\
version: 1
image:
  suffix: "-devcontainer"
  config_dir: ".devcontainer/.dev"
  userdata_dir: "/tmp/devcontainer-userdata"
  cache_ref_prefix: cache
  build_matrix:
    - runner: ubuntu-latest
      platform: linux/amd64
      platform_tag: linux-amd64
artifacts:
  retention_days: 7
  src:
    name: devfeats-src
    path: src/
  dist:
    name: devfeats-dist
    path: dist/
  pages:
    name: github-pages
    path: .local/build/docs/website.tar
publish:
  registry: ghcr.io
  git_bot:
    name: "github-actions[bot]"
    email: "41898282+github-actions[bot]@users.noreply.github.com"
  pages_environment: github-pages
runner:
  free_disk_space:
    tool_cache: true
    swap_storage: true
    docker_images: true
    android: true
    dotnet: true
    haskell: true
    large_packages: true
scripts:
  features_src: "./src"
triggers:
  lint: ["**/*.sh"]
  validate: ["**/metadata.yaml"]
  unit_test: ["lib/*.sh"]
  scenario_test: ["features/install.sh"]
  devcontainer: [".devcontainer/.dev/**"]
  docs: ["docs/**"]
  python_test: [".dev/lib/**"]
"""


def test_load_project_returns_name(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_project returns the project name and version from YAML."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    proj = cfg.load_project()
    assert proj["name"] == "testproject"
    assert proj["version"] == 1


def test_load_ci_image_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_ci parses the image section correctly."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    ci = cfg.load_ci()
    assert ci["image"]["suffix"] == "-devcontainer"
    assert ci["image"]["config_dir"] == ".devcontainer/.dev"
    assert isinstance(ci["image"]["build_matrix"], list)
    assert ci["image"]["build_matrix"][0]["platform"] == "linux/amd64"


def test_load_ci_artifacts_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_ci parses the artifacts section correctly."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    ci = cfg.load_ci()
    assert ci["artifacts"]["retention_days"] == 7
    assert ci["artifacts"]["src"]["name"] == "devfeats-src"
    assert ci["artifacts"]["dist"]["path"] == "dist/"
    assert ci["artifacts"]["pages"]["name"] == "github-pages"
    assert ci["artifacts"]["pages"]["path"] == ".local/build/docs/website.tar"


def test_load_ci_publish_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_ci parses the publish section correctly."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    ci = cfg.load_ci()
    assert ci["publish"]["registry"] == "ghcr.io"
    assert ci["publish"]["git_bot"]["name"] == "github-actions[bot]"
    assert ci["publish"]["pages_environment"] == "github-pages"


def test_load_ci_triggers_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_ci parses the triggers section correctly."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    ci = cfg.load_ci()
    assert "lint" in ci["triggers"]
    assert "**/*.sh" in ci["triggers"]["lint"]
    assert "python_test" in ci["triggers"]


def test_load_ci_runner_free_disk_space(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_ci parses the runner free_disk_space flags correctly."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    ci = cfg.load_ci()
    fds = ci["runner"]["free_disk_space"]
    assert fds["tool_cache"] is True
    assert fds["large_packages"] is True


def test_load_project_is_cached(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_project returns the same object on repeated calls."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    assert cfg.load_project() is cfg.load_project()


def test_load_ci_is_cached(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load_ci returns the same object on repeated calls."""
    _patch_loaders(monkeypatch, tmp_path, _MINIMAL_PROJECT, _MINIMAL_CI)
    assert cfg.load_ci() is cfg.load_ci()
