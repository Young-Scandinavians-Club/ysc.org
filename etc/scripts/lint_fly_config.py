#!/usr/bin/env python3
"""Lint (and optionally rewrite) Fly.io config files so they stay easy to read.

Rules, applied to every tracked ``fly*.toml``:

  1. Top-level sections follow one canonical order (see SECTION_ORDER).
  2. Keys inside ``[env]`` are sorted alphabetically.
  3. String values use TOML literal ('single') quotes unless they need
     double quotes (they contain a single quote or an escape sequence).
  4. Sections are separated by exactly one blank line; no trailing whitespace;
     the file ends with a single newline.

Usage:
  lint_fly_config.py            check all tracked fly*.toml files (exit 1 on drift)
  lint_fly_config.py --fix      rewrite files in place
  lint_fly_config.py FILE...    check (or --fix) only the given files
  lint_fly_config.py --self-test
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Sections not listed here sort after these, in their original order.
SECTION_ORDER = [
    "build",
    "deploy",
    "env",
    "http_service",
    "http_service.concurrency",
    "http_service.checks",
    "vm",
    "metrics",
]

HEADER_RE = re.compile(r"^\s*\[\[?\s*([A-Za-z0-9_.\-]+)\s*\]\]?\s*(#.*)?$")
FLY_FILE_RE = re.compile(r"^fly.*\.toml$")
ENV_ENTRY_RE = re.compile(r"^([A-Za-z0-9_\-]+)\s*=\s*(.*)$")


def section_rank(name: str | None) -> int:
    if name is None:
        return -1
    # Child tables like [http_service.checks.headers] must stay beside their parent.
    if name.startswith("http_service.checks."):
        return SECTION_ORDER.index("http_service.checks")
    if name in SECTION_ORDER:
        return SECTION_ORDER.index(name)
    return len(SECTION_ORDER)


def normalize_quotes(text: str) -> str:
    """Convert simple "double" strings to 'literal' strings; leave the rest alone."""
    out: list[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "#":
            out.append(text[i:])
            break
        if ch == "'":
            end = text.find("'", i + 1)
            end = len(text) - 1 if end == -1 else end
            out.append(text[i : end + 1])
            i = end + 1
        elif ch == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            body = text[i + 1 : j]
            if j < len(text) and "'" not in body and "\\" not in body:
                out.append(f"'{body}'")
            else:
                out.append(text[i : j + 1])
            i = j + 1
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def parse_sections(lines: list[str]):
    """Split into (preamble, sections). A section is (name, leading_comments, header, body)."""
    preamble: list[str] = []
    sections: list[tuple[str, list[str], str, list[str]]] = []
    pending_comments: list[str] = []
    current = None

    def flush_pending_into_body():
        nonlocal pending_comments
        target = current[3] if current else preamble
        target.extend(pending_comments)
        pending_comments = []

    for line in lines:
        header = HEADER_RE.match(line)
        if header:
            name = header.group(1)
            leading = pending_comments
            pending_comments = []
            current = (name, leading, line.strip(), [])
            sections.append(current)
        elif line.lstrip().startswith("#"):
            pending_comments.append(line.rstrip())
        else:
            flush_pending_into_body()
            (current[3] if current else preamble).append(line.rstrip())
    flush_pending_into_body()
    return preamble, sections


def trim_blank(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and lines[start] == "":
        start += 1
    while end > start and lines[end - 1] == "":
        end -= 1
    return lines[start:end]


def format_env_body(body: list[str]) -> list[str]:
    """Sort KEY = value entries; keep each entry's leading comment lines attached."""
    entries: list[tuple[str, list[str]]] = []
    comments: list[str] = []
    for line in trim_blank(body):
        if line.startswith("#"):
            comments.append(line)
            continue
        match = ENV_ENTRY_RE.match(line)
        if not match:
            return body  # something unusual (multi-line value); leave untouched
        key, value = match.groups()
        entries.append((key, comments + [f"{key} = {normalize_quotes(value)}"]))
        comments = []
    if comments:
        return body
    entries.sort(key=lambda entry: entry[0])
    return [line for _, chunk in entries for line in chunk]


def format_text(text: str) -> str:
    lines = [line.rstrip() for line in text.splitlines()]
    preamble, sections = parse_sections(lines)

    indexed = list(enumerate(sections))
    indexed.sort(key=lambda pair: (section_rank(pair[1][0]), pair[0]))

    blocks: list[list[str]] = []
    preamble = [normalize_quotes(line) if "=" in line else line for line in trim_blank(preamble)]
    if preamble:
        blocks.append(preamble)
    for _, (name, leading, header, body) in indexed:
        body = trim_blank(body)
        if name == "env":
            body = format_env_body(body)
        else:
            body = [normalize_quotes(line) if "=" in line else line for line in body]
        blocks.append(leading + [header] + body)

    return "\n\n".join("\n".join(block) for block in blocks) + "\n"


def tracked_fly_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.toml"],
        check=True,
        capture_output=True,
        text=True,
    )
    return sorted(
        {
            path
            for path in result.stdout.splitlines()
            if FLY_FILE_RE.match(Path(path).name) and Path(path).is_file()
        }
    )


def run(paths: list[str], fix: bool) -> int:
    drifted = []
    for path in paths:
        original = Path(path).read_text()
        formatted = format_text(original)
        if formatted == original:
            continue
        drifted.append(path)
        if fix:
            Path(path).write_text(formatted)
            print(f"fixed {path}")
        else:
            print(f"{path}: not formatted")
    if drifted and not fix:
        print("\nFly config files need formatting. Run 'make format' (or etc/scripts/lint_fly_config.py --fix).")
        return 1
    return 0


def self_test() -> int:
    messy = (
        '# header\n'
        'app = "demo"\n'
        '\n'
        '[metrics]\n'
        'port = 4000\n'
        '\n'
        '[env]\n'
        'ZED = "z"\n'
        '# about alpha\n'
        'ALPHA = "a"\n'
        'QUOTED = "has \'quote\'"\n'
        'LIST = ["a", "b"]\n'
        '\n'
        '\n'
        '[build]\n'
        'dockerfile = "Dockerfile"   \n'
    )
    expected = (
        '# header\n'
        "app = 'demo'\n"
        '\n'
        '[build]\n'
        "dockerfile = 'Dockerfile'\n"
        '\n'
        '[env]\n'
        '# about alpha\n'
        "ALPHA = 'a'\n"
        "LIST = ['a', 'b']\n"
        'QUOTED = "has \'quote\'"\n'
        "ZED = 'z'\n"
        '\n'
        '[metrics]\n'
        'port = 4000\n'
    )
    checks = (
        '[[vm]]\n'
        "size = 'x'\n"
        '\n'
        '[[http_service.checks]]\n'
        "path = '/a'\n"
        '\n'
        '[http_service.checks.headers]\n'
        "X-A = '1'\n"
        '\n'
        '[[http_service.checks]]\n'
        "path = '/b'\n"
        '\n'
        '[http_service.checks.headers]\n'
        "X-B = '2'\n"
        '\n'
        '[http_service]\n'
        'internal_port = 4000\n'
    )
    kept = format_text(checks)
    assert kept.index("[http_service]") < kept.index("path = '/a'") < kept.index("X-A") < kept.index("path = '/b'") < kept.index("X-B") < kept.index("[[vm]]"), kept
    got = format_text(messy)
    assert got == expected, f"unexpected output:\n{got}"
    assert format_text(got) == got, "formatter is not idempotent"
    print("lint_fly_config self-test passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="*")
    parser.add_argument("--fix", action="store_true", help="rewrite files in place")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    return run(args.files or tracked_fly_files(), args.fix)


if __name__ == "__main__":
    sys.exit(main())
