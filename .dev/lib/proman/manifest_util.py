"""Utilities for serializing ospkg manifest blocks from feature metadata."""

from __future__ import annotations

import re

import pyserials


def serialize_manifest(content: dict) -> str:
    r"""Serialize a manifest dict to YAML for option ``default`` values.

    Non-empty output always ends with a trailing newline so ``ospkg__run`` treats
    the value as inline YAML rather than a URI/path, and so ``install.bash``
    codegen emits ANSI-C-quoted defaults (preserving embedded single quotes).

    Output is unescaped canonical YAML. Devcontainer-specific escaping for
    ``devcontainer-feature.json`` defaults is applied separately by
    :func:`escape_devcontainer_default` during sync.
    """
    return (
        pyserials.write.to_yaml_string(
            content,
            end_of_file_newline=True,
        )
        if content
        else ""
    )


def escape_devcontainer_default(value: str) -> str:
    r"""Escape ``$`` and ``"`` for ``devcontainer-feature.json`` option defaults.

    The devcontainer CLI wraps every option value in double quotes when writing
    ``devcontainer-features.env`` and may also surface defaults in Dockerfile
    ``ENV`` instructions. Escaping prevents premature shell expansion and keeps
    multiline values syntactically valid.

    Already-escaped sequences (``\$``, ``\"``) are left unchanged so metadata
    defaults that intentionally use ``\${VAR}`` (e.g. ``runtime_path``) are not
    double-escaped.
    """
    if not value:
        return value
    return re.sub(r'(?<!\\)([$"])', r"\\\1", value)


def generate_dep_trigger_specs(metadata: dict) -> list[str]:
    """Return tab-separated trigger spec lines for option-bound manifest installs."""
    options: dict = metadata.get("options") or {}
    lines: list[str] = []

    for group in metadata.get("_dependencies", {}).get("run", {}):
        if not group.startswith("option-"):
            continue
        name = group.removeprefix("option-")
        opt = options.get(name)
        if not opt or opt.get("type") != "boolean":
            continue
        manifest_var = f"OSPKG_MANIFEST_OPTION_{name.upper().replace('-', '_')}"
        boolean_var = name.upper().replace("-", "_")
        lines.append(f"{name}\t{manifest_var}\t{boolean_var}")

    return lines
