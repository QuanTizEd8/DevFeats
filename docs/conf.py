# Configuration file for the Sphinx documentation builder.
# https://www.sphinx-doc.org/en/master/usage/configuration.html

from __future__ import annotations

from pathlib import Path
import sys as _sys
from typing import TYPE_CHECKING

import yaml as _yaml  # noqa: E402 (pyyaml; available in sysset-website env via myst-parser)

if TYPE_CHECKING:
    from sphinx.application import Sphinx


_REPO = Path(__file__).resolve().parent.parent
_sys.path.insert(0, str(_REPO / "scripts"))

from parse_feature_json import render_options_table as _render_options_table  # noqa: E402


def setup(app):
    """Register lexer aliases and connect build-time feature preamble injection."""
    from pygments.lexers.data import JsonLexer
    from pygments.lexers.configs import IniLexer

    app.add_lexer("jsonc", JsonLexer)
    app.add_lexer("gitconfig", IniLexer)
    app.connect("source-read", _inject_feature_preamble)
    app.connect("source-read", _source_jinja_template)
    return


def _load_feature_metadata() -> dict[str, dict]:
    """Load feature metadata from all features' metadata.yaml files into a dict."""
    metadata = {}
    for meta_path in (_REPO / "features").glob("*/metadata.yaml"):
        with meta_path.open(encoding="utf-8") as fh:
            data = _yaml.safe_load(fh)
        feat_id = data["id"]
        metadata[feat_id] = data
    return metadata


def _inject_feature_preamble(app, docname: str, source):  # noqa: ANN001
    """Prepend H1 + description + options table to feature reference pages."""
    # ── Feature reference preamble injection ───────────────────────────────────────
    # At build time, prepend each feature's H1 title, description, and ## Options
    # table to the stripped reference pages.
    #
    # metadata.yaml is the single source of truth.  The raw markdown description
    # (including links) is used verbatim so MyST renders it correctly.  The
    # ## Options table is generated from the options dict in metadata.yaml.
    # devcontainer-feature.json is a generated artifact and not read here.

    if not docname.startswith("features/"):
        return
    if docname.endswith("/index"):
        return

    feature_id = docname.split("/")[-1]
    feature = _feature_metadata.get(feature_id)
    if not feature:
        raise ValueError(f"Feature metadata not found for feature ID '{feature_id}'")

    feature_name = feature["name"]
    # Use the raw description from YAML verbatim so markdown links render.
    desc_raw = (feature["description"]).strip()
    options_block = _render_options_table(feature)

    parts = [f"# {feature_name}"]
    if desc_raw:
        parts.append(desc_raw)
    if options_block:
        parts.append(options_block)
    parts.append("---\n")
    preamble = "\n\n".join(parts) + "\n"
    source[0] = preamble + source[0]


def _source_jinja_template(app: Sphinx, docname: str, content: list[str]) -> None:
    """Render pages as jinja template for templating inside source files.

    References
    ----------
    - https://www.ericholscher.com/blog/2016/jul/25/integrating-jinja-rst-sphinx/
    - https://www.sphinx-doc.org/en/master/extdev/event_callbacks.html#event-source-read
    """
    error_msg = (
        f"Could not render page '{docname}' as Jinja template. "
        "Please ensure that the page content is valid."
    )
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
        raise RuntimeError(error_msg) from e
    # Revert Jinja environment markers to their defaults
    # so that other templates and tools have the default markers.
    for attr, attr_val in attrs_default.items():
        setattr(app.builder.templates.environment, attr, attr_val)
    return


_feature_metadata = _load_feature_metadata()


# ── Project information ────────────────────────────────────────────────────────

project = "SysSet"
copyright = "2024–2025, SysSet contributors"
author = "SysSet contributors"

# ── General configuration ──────────────────────────────────────────────────────

extensions = [
    # Core Markdown + notebook support
    "myst_parser",
    # External TOC (docs/_toc.yml)
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

# sphinx-external-toc: path relative to confdir
external_toc_path = "_toc.yml"
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
html_title = "SysSet"
html_logo = None  # add docs/_static/logo.svg when available

html_theme_options = {
    "github_url": "https://github.com/quantized8/sysset",
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
    "github_user": "quantized8",
    "github_repo": "sysset",
    "github_version": "main",
    "doc_path": "docs",
    "feats": _feature_metadata,  # for Jinja templating in source files
}

html_static_path = ["_static"]
html_css_files = []

# sphinx-copybutton: strip prompt characters from copied shell blocks
copybutton_prompt_text = r"^\$ |^# "
copybutton_prompt_is_regexp = True

# sphinxcontrib-bibtex
bibtex_bibfiles = []


# ── OpenGraph ──────────────────────────────────────────────────────────────────

ogp_site_url = "https://quantized8.github.io/sysset/"
ogp_description_length = 200
