# Configuration file for the Sphinx documentation builder.
# https://www.sphinx-doc.org/en/master/usage/configuration.html

from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING

import yaml

if TYPE_CHECKING:
    from typing import Any
    from sphinx.application import Sphinx

_WEBSITE_ROOT = Path(__file__).resolve().parent
_REPO_ROOT = _WEBSITE_ROOT.parent
_DOCS_DATA_PATH = _REPO_ROOT / ".dev" / "output" / "docs-data.json"

_docs_cfg: dict = yaml.safe_load(
    (_REPO_ROOT / ".dev/config/docs.yaml").read_text(encoding="utf-8")
)["sphinx"]
globals().update(_docs_cfg)

if not _DOCS_DATA_PATH.exists():
    raise FileNotFoundError(
        f"Docs data artifact not found: {_DOCS_DATA_PATH}\n"
        "Run 'pixi run gen-docs-data' before building the docs."
    )

_docs_data: dict[str, Any] = json.loads(_DOCS_DATA_PATH.read_text(encoding="utf-8"))
_REPO_OWNER: str = _docs_data["repo_owner"]
_REPO_NAME: str = _docs_data["repo_name"]
_feature_metadata: dict[str, dict[str, Any]] = _docs_data["features"]
_lib_modules: dict[str, str] = _docs_data.get("lib_modules", {})


def setup(app):
    """Register lexer aliases and connect build-time feature preamble injection."""
    from pygments.lexers.data import JsonLexer
    from pygments.lexers.configs import IniLexer

    app.add_lexer("jsonc", JsonLexer)
    app.add_lexer("gitconfig", IniLexer)
    app.connect("source-read", _source_jinja_template)
    return


def _source_jinja_template(app: Sphinx, docname: str, content: list[str]) -> None:
    """Render pages as jinja template for templating inside source files.

    References
    ----------
    - https://www.ericholscher.com/blog/2016/jul/25/integrating-jinja-rst-sphinx/
    - https://www.sphinx-doc.org/en/master/extdev/event_callbacks.html#event-source-read
    """
    # Change Jinja environment markers to avoid clashes with the MyST Attributes extension
    # as well as templating syntax in control center configurations.
    # Refs:
    # - Jinja: https://jinja.palletsprojects.com/en/stable/api/#jinja2.Environment
    # - MyST: https://myst-parser.readthedocs.io/en/latest/syntax/optional.html#attributes
    attrs_default = {}
    for attr, attr_new_val in (
        ("block_start_string", "|{%"),
        ("block_end_string", "%}|"),
        ("variable_start_string", "|{{"),
        ("variable_end_string", "}}|"),
        ("comment_start_string", "|{#"),
        ("comment_end_string", "#}|"),
    ):
        attr_val = getattr(app.builder.templates.environment, attr)
        attrs_default[attr] = attr_val
        setattr(app.builder.templates.environment, attr, attr_new_val)
    # Run page through Jinja
    try:
        content[0] = app.builder.templates.render_string(
            content[0],
            app.config.html_context | {"docname": app.env.docname},
        )
    except Exception as e:
        full_path = app.env.doc2path(docname)
        raise RuntimeError(
            f"Could not render '{full_path}' as Jinja template "
            f"(in {__name__}._source_jinja_template): "
            f"{type(e).__name__}: {e}"
        ) from e
    # Revert Jinja environment markers to their defaults
    # so that other templates and tools have the default markers.
    for attr, attr_val in attrs_default.items():
        setattr(app.builder.templates.environment, attr, attr_val)
    return


# ── Project information ────────────────────────────────────────────────────────

project = _REPO_NAME
copyright = f"2024–2025, {_REPO_NAME} contributors"
author = f"{_REPO_NAME} contributors"

# ── General configuration ──────────────────────────────────────────────────────

# sphinx-external-toc: absolute path keeps this stable even when callers vary -c/confdir.
external_toc_path = str(_WEBSITE_ROOT / "toc.yaml")

# ── HTML output ────────────────────────────────────────────────────────────────

html_title = _REPO_NAME

html_theme_options = _docs_cfg["html_theme_options"] | {
    "github_url": f"https://github.com/{_REPO_OWNER}/{_REPO_NAME}",
}

html_context = _docs_cfg["html_context"] | {
    "project_name": _REPO_NAME,
    "github_user": _REPO_OWNER,
    "github_repo": _REPO_NAME,
    "feats": _feature_metadata,
    "lib_modules": _lib_modules,
}

# ── OpenGraph ──────────────────────────────────────────────────────────────────

ogp_site_url = f"https://{_REPO_OWNER.lower()}.github.io/{_REPO_NAME.lower()}/"
