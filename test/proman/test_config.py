"""Round-trip tests for proman.config loaders."""

from __future__ import annotations

from typing import TYPE_CHECKING

import proman.config as cfg
import pytest

if TYPE_CHECKING:
    from pathlib import Path

_MINIMAL_MAIN = """\
name: TestProject
name_slug: testproject
owner: testowner
owner_slug: testowner
namespace: testowner/testproject
repo_url: https://github.com/testowner/testproject
oci_base: ghcr.io/testowner/testproject
path:
  features: features
  library: lib
  feature_library: ${{ path.library }}$
  src: src
  test: test
  test_features: ${{ path.test }}$/features
  test_features_shared_defaults: ${{ path.test_features }}$/defaults.shared.yaml
  test_environments: ${{ path.test }}$/environments.yaml
  dev_scripts_test: .dev/scripts/test
  test_run_in_container: ${{ path.dev_scripts_test }}$/run-in-container.sh
  local_logs_features: .local/logs/tests/features
  devcontainer: .devcontainer
  shared_metadata: features/metadata.shared.yaml
  metadata_schema: features/metadata.schema.json
  install_script_template: features/install.tmpl.bash
filename:
  feature_metadata: metadata.yaml
  feature_script: install.bash
  feature_scenarios: scenarios.yaml
features:
  lifecycle_hook_keys:
    - onCreateCommand
"""

_MINIMAL_CI = """\
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
    name: testproject-src
    path: src/
  dist:
    name: testproject-dist
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
  lint: ["**/*.sh", "**/*.bash"]
  validate: ["**/metadata.yaml"]
  unit_test: ["lib/*.sh", "lib/*.bash"]
  scenario_test: ["features/install.sh"]
  devcontainer: [".devcontainer/.dev/**"]
  docs: ["docs/**"]
  python_test: [".dev/lib/**"]
"""


@pytest.fixture(autouse=True)
def _reset_config_singleton() -> None:
    """Ensure isolated tests do not leave a patched config singleton."""
    yield
    cfg.clear_cache()


def _patch_loaders(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    main_yaml: str = _MINIMAL_MAIN,
    ci_yaml: str = _MINIMAL_CI,
) -> None:
    """Write proman YAML files to tmp_path and redirect loaders to read them."""
    proman_dir = tmp_path / ".config" / "proman"
    proman_dir.mkdir(parents=True)
    (proman_dir / "_main.yaml").write_text(main_yaml, encoding="utf-8")
    (proman_dir / "ci.yaml").write_text(ci_yaml, encoding="utf-8")
    monkeypatch.setattr(cfg, "git_repo_root", lambda: tmp_path)
    cfg.clear_cache()


def test_load_returns_project_name(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load() exposes project name from _main.yaml."""
    _patch_loaders(monkeypatch, tmp_path)
    config = cfg.load()
    assert config["name"] == "TestProject"
    assert config["name_slug"] == "testproject"
    assert config["path.library"] == "lib"
    assert config["path.feature_library"] == "lib"


def test_load_ci_image_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify ci.yaml image section is merged into config."""
    _patch_loaders(monkeypatch, tmp_path)
    ci = cfg.load()["ci"]
    assert ci["image"]["suffix"] == "-devcontainer"
    assert ci["image"]["config_dir"] == ".devcontainer/.dev"
    assert isinstance(ci["image"]["build_matrix"], list)
    assert ci["image"]["build_matrix"][0]["platform"] == "linux/amd64"


def test_load_ci_artifacts_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify ci.yaml artifacts section is merged into config."""
    _patch_loaders(monkeypatch, tmp_path)
    ci = cfg.load()["ci"]
    assert ci["artifacts"]["retention_days"] == 7
    assert ci["artifacts"]["src"]["name"] == "testproject-src"
    assert ci["artifacts"]["dist"]["path"] == "dist/"
    assert ci["artifacts"]["pages"]["name"] == "github-pages"
    assert ci["artifacts"]["pages"]["path"] == ".local/build/docs/website.tar"


def test_load_ci_publish_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify ci.yaml publish section is merged into config."""
    _patch_loaders(monkeypatch, tmp_path)
    ci = cfg.load()["ci"]
    assert ci["publish"]["registry"] == "ghcr.io"
    assert ci["publish"]["git_bot"]["name"] == "github-actions[bot]"
    assert ci["publish"]["pages_environment"] == "github-pages"


def test_load_ci_triggers_section(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify ci.yaml triggers section is merged into config."""
    _patch_loaders(monkeypatch, tmp_path)
    ci = cfg.load()["ci"]
    assert "lint" in ci["triggers"]
    assert "**/*.sh" in ci["triggers"]["lint"]
    assert "**/*.bash" in ci["triggers"]["lint"]
    assert "lib/*.bash" in ci["triggers"]["unit_test"]
    assert "python_test" in ci["triggers"]


def test_load_ci_runner_free_disk_space(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify ci.yaml runner free_disk_space flags are merged into config."""
    _patch_loaders(monkeypatch, tmp_path)
    ci = cfg.load()["ci"]
    fds = ci["runner"]["free_disk_space"]
    assert fds["tool_cache"] is True
    assert fds["large_packages"] is True


def test_load_is_cached(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify load() returns the same Config instance on repeated calls."""
    _patch_loaders(monkeypatch, tmp_path)
    assert cfg.load() is cfg.load()


def test_absolute_path(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Verify absolute_path resolves paths relative to the repo root."""
    _patch_loaders(monkeypatch, tmp_path)
    config = cfg.load()
    assert config.absolute_path("path.features") == tmp_path / "features"
    assert config.absolute_path("path.test_features") == tmp_path / "test" / "features"
    assert config.absolute_path("path.test_features_shared_defaults") == (
        tmp_path / "test" / "features" / "defaults.shared.yaml"
    )
    assert config.absolute_path("path.local_logs_features") == (
        tmp_path / ".local" / "logs" / "tests" / "features"
    )
    assert config.absolute_path("path.test_run_in_container") == (
        tmp_path / ".dev" / "scripts" / "test" / "run-in-container.sh"
    )
    assert config["filename.feature_scenarios"] == "scenarios.yaml"
