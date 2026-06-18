"""Utilities for serializing ospkg manifest blocks from feature metadata."""

from __future__ import annotations

import pyserials


def serialize_manifest(content: dict) -> str:
    """Serialize a manifest dict to YAML for option ``default`` values.

    Non-empty output always ends with a trailing newline so ``ospkg__run`` treats
    the value as inline YAML rather than a URI/path, and so ``install.bash``
    codegen emits ANSI-C-quoted defaults (preserving embedded single quotes).
    Shell escaping itself is applied later by ``InstallScriptGenerator._shell_val``.
    """
    return (
        pyserials.write.to_yaml_string(
            content,
            end_of_file_newline=True,
        )
        if content
        else ""
    )


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
