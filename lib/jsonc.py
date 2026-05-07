#!/usr/bin/env python3
# jsonc.py — JSONC → JSON (strip comments) and duplicate-key checks for lib/json.sh helpers.
# Stdlib only. Invoked: python3 jsonc.py strip | dup [objectKey]
from __future__ import annotations

import json
import sys
from typing import Any

_WS = set(" \t\n\r")


def _strip_comments(text: str) -> str:
    """Remove // and /* */ only outside JSON strings. Assume valid-ish JSON/JSONC."""
    out: list[str] = []
    i = 0
    n = len(text)
    in_string = False
    escape = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c in _WS or c in "{}[]:,":
            out.append(c)
            i += 1
            continue
        if c == "/":
            if i + 1 < n and text[i + 1] == "/":
                i += 2
                while i < n and text[i] not in "\r\n":
                    i += 1
                continue
            if i + 1 < n and text[i + 1] == "*":
                i += 2
                while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                    i += 1
                i = min(n, i + 2)
                continue
        out.append(c)
        i += 1
    return "".join(out)


def _trailing_commas(text: str) -> str:
    s = _trailing_commas_once(text)
    while s != text:
        text = s
        s = _trailing_commas_once(text)
    return s


def _trailing_commas_once(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    in_string = False
    escape = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c == ",":
            j = i + 1
            while j < n and text[j] in _WS:
                j += 1
            if j < n and text[j] in "}]":
                i = j
                continue
        out.append(c)
        i += 1
    return "".join(out)


def strip_jsonc(text: str) -> str:
    s0 = _strip_comments(text)
    return _trailing_commas(s0)


def _strict_pairs(
    pairs: list[tuple[str, Any]],
) -> Any:
    """object_pairs_hook — called for every JSON object; reject duplicate keys."""
    d: Any = {}
    for k, v in pairs:
        if k in d:
            print(f"duplicate key: {k}", file=sys.stderr)
            raise ValueError("duplicate key")
        d[k] = v
    return d


def _parse_dup(text: str) -> None:
    s = strip_jsonc(text)
    json.loads(s, object_pairs_hook=_strict_pairs)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: jsonc.py strip|dup [objectKey]", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    raw = sys.stdin.read()
    if cmd == "strip":
        try:
            s = strip_jsonc(raw)
            json.loads(s)
        except (ValueError, json.JSONDecodeError) as e:
            print(str(e), file=sys.stderr)
            return 1
        sys.stdout.write(s)
        return 0
    if cmd == "dup":
        # Optional objectKey is accepted for forward compatibility; detection is for all objects.
        try:
            _parse_dup(raw)
        except (ValueError, json.JSONDecodeError) as e:
            print(str(e), file=sys.stderr)
            return 1
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
