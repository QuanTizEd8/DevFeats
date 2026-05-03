# Configuration file for the Sphinx documentation builder.
# https://www.sphinx-doc.org/en/master/usage/configuration.html

from __future__ import annotations

from pathlib import Path
import sys
from typing import TYPE_CHECKING

import yaml as _yaml

if TYPE_CHECKING:
    from typing import Any
    from sphinx.application import Sphinx

_WEBSITE_ROOT = Path(__file__).resolve().parent
_WEBSITE_SOURCE_DIR = _WEBSITE_ROOT / "source"
_REPO_ROOT = _WEBSITE_ROOT.parent
_FEATURES_DIR = _REPO_ROOT / "features"
_FEATURES_DOC_DIR = _WEBSITE_SOURCE_DIR / "features"
_FEATURES_NOTES_FILENAME = "NOTES.md"

from proman import feat_doc_gen, git_utils


_REPO_OWNER, _REPO_NAME = git_utils.git_owner_repo()


def setup(app):
    """Register lexer aliases and connect build-time feature preamble injection."""
    from pygments.lexers.data import JsonLexer
    from pygments.lexers.configs import IniLexer

    app.add_lexer("jsonc", JsonLexer)
    app.add_lexer("gitconfig", IniLexer)
    app.connect("source-read", _source_jinja_template)
    return


def _load_feature_metadata() -> dict[str, dict[str, Any]]:
    """Load feature metadata from all features' metadata.yaml files into a dict."""
    all_metadata: dict[str, dict[str, Any]] = {}
    for meta_path in sorted(_FEATURES_DIR.glob("*/metadata.yaml")):
        with meta_path.open(encoding="utf-8") as fh:
            feat_metadata = _yaml.safe_load(fh)
        feat_id = meta_path.parent.name
        feat_metadata["id"] = feat_id
        all_metadata[feat_id] = feat_metadata
    return all_metadata


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


def _update_source_file(path: Path, content: str) -> None:
    """Write file only when content differs to keep builds idempotent.

    This prevents sphinx-autobuild from retriggering on no-op writes.
    """
    if path.exists() and path.read_text() == content:
        return
    path.write_text(content)
    return


def _generate_docs(metadata: dict[str, dict]) -> None:
    """Generate auto-generated docs."""
    _FEATURES_DOC_DIR.mkdir(parents=True, exist_ok=True)
    for feat_id, feat_metadata in metadata.items():
        feat_notes_path = _FEATURES_DIR / feat_id / _FEATURES_NOTES_FILENAME
        feat_notes = feat_notes_path.read_text() if feat_notes_path.exists() else ""
        feat_doc = feat_doc_gen.generate(
            metadata=feat_metadata,
            notes=feat_notes,
        )
        feat_doc_path = _FEATURES_DOC_DIR / f"{feat_id}.md"
        _update_source_file(feat_doc_path, feat_doc)
    return


_feature_metadata = _load_feature_metadata()
_generate_docs(_feature_metadata)


# ── Project information ────────────────────────────────────────────────────────

project = _REPO_NAME
copyright = f"2024–2025, {_REPO_NAME} contributors"
author = f"{_REPO_NAME} contributors"

# ── General configuration ──────────────────────────────────────────────────────

extensions = [
    # Core Markdown + notebook support
    "myst_parser",
    # External TOC (docs/toc.yaml)
    "sphinx_external_toc",
    # pydata theme extras
    "sphinx_design",
    "sphinx_copybutton",
    "sphinx_togglebutton",
    # Diagrams
    "sphinxcontrib.mermaid",
    # OpenGraph meta tags
    "sphinxext.opengraph",
    # Last-updated timestamps from git
    "sphinx_last_updated_by_git",
    # 404 page
    "notfound.extension",
    # Bibliography / cite role
    "sphinxcontrib.bibtex",
]

# sphinx-external-toc: absolute path keeps this stable even when callers vary -c/confdir.
external_toc_path = str(_WEBSITE_ROOT / "toc.yaml")
external_toc_exclude_missing = False

# MyST options
myst_enable_extensions = [
    "colon_fence",      # ::: directive shorthand
    "deflist",          # definition lists
    "fieldlist",        # field lists
    "substitution",     # |sub| substitutions
    "tasklist",         # - [ ] checkboxes
    "attrs_inline",     # inline attribute syntax
]
myst_heading_anchors = 3
myst_links_external_new_tab = True

suppress_warnings = [
    "myst.xref_missing",         # suppress missing cross-ref warnings during early dev
    "bibtex.key_not_found",      # .bib file not yet populated
    "misc.highlighting_failure", # jsonc blocks with ... ellipsis retry in relaxed mode (harmless)
    "etoc.toctree",              # sphinx-external-toc manages all toctrees
]

templates_path = ["_templates"]
exclude_patterns = [
    "_build",
    "website",
    "**.ipynb_checkpoints",
    "environment.yaml",
    # Flat stub superseded by ref/install-pixi/ subdirectory
    "ref/install-pixi.md",
]

# ── HTML output ────────────────────────────────────────────────────────────────

html_theme = "pydata_sphinx_theme"
html_title = _REPO_NAME
html_logo = None  # add docs/_static/logo.svg when available

html_theme_options = {
    "github_url": f"https://github.com/{_REPO_OWNER}/{_REPO_NAME}",
    "use_edit_page_button": True,
    "show_toc_level": 2,
    "navigation_with_keys": True,
    "navbar_align": "left",
    "footer_start": ["copyright"],
    "footer_end": ["theme-version"],
    "secondary_sidebar_items": ["page-toc", "edit-this-page", "sourcelink"],
    "pygments_light_style": "friendly",
    "pygments_dark_style": "monokai",
}

html_context = {
    "project_name": _REPO_NAME,
    "github_user": _REPO_OWNER,
    "github_repo": _REPO_NAME,
    "github_version": "main",
    "doc_path": "docs/source",
    "feats": _feature_metadata,  # for Jinja templating in source files
    "lib_modules": {},  # TODO: populate with module metadata for doc generation and templating
}

html_static_path = ["_static"]
html_css_files = []

# sphinx-copybutton: strip prompt characters from copied shell blocks
copybutton_prompt_text = r"^\$ |^# "
copybutton_prompt_is_regexp = True

# sphinxcontrib-bibtex
bibtex_bibfiles = []


# ── OpenGraph ──────────────────────────────────────────────────────────────────

ogp_site_url = f"https://{_REPO_OWNER.lower()}.github.io/{_REPO_NAME.lower()}/"
ogp_description_length = 200
