#!/usr/bin/env python3
"""Rewrite typed function calls inside assert_raise blocks to use Ysc.Test.Invoke.call/3."""

from __future__ import annotations

import re
import sys
from pathlib import Path

FUNCS = frozenset(
    {
        "prepare_email_data",
        "prepare_sms_data",
        "membership_payment_reminder_data",
    }
)

CALL_START = re.compile(
    r"([\w\.]+)\.(prepare_email_data|prepare_sms_data|membership_payment_reminder_data)\s*\("
)
ASSERT_RAISE_START = re.compile(r"\bassert_raise\b")


def find_matching_end(lines: list[str], start: int) -> int:
    depth = 0

    for i in range(start, len(lines)):
        line = lines[i]

        if re.search(r"\bfn\s*->", line):
            depth += 1

        if re.search(r"\bend\b", line):
            depth -= 1
            if depth == 0:
                return i

    raise ValueError(f"no matching end for block starting at line {start + 1}")


def split_call_args(args: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth = 0

    for char in args:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1

        if char == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
            continue

        current.append(char)

    tail = "".join(current).strip()
    if tail:
        parts.append(tail)

    return parts


def rewrite_call(module: str, func: str, args: str, indent: str) -> str:
    arg_list = split_call_args(args)
    formatted_args = ",\n".join(f"{indent}  {arg}" for arg in arg_list)
    multiline = len(arg_list) > 1 or any("\n" in arg for arg in arg_list)

    if multiline:
        return (
            f"{indent}Ysc.Test.Invoke.call({module}, :{func}, [\n"
            f"{formatted_args}\n"
            f"{indent}])"
        )

    return f"{indent}Ysc.Test.Invoke.call({module}, :{func}, [{args.strip()}])"


def extract_call(text: str, open_paren: int) -> tuple[str, int]:
    depth = 0
    args_chars: list[str] = []

    for i in range(open_paren, len(text)):
        char = text[i]

        if char == "(":
            depth += 1
            if depth == 1:
                continue

        if char == ")":
            depth -= 1
            if depth == 0:
                return "".join(args_chars), i + 1

        if depth >= 1:
            args_chars.append(char)

    raise ValueError("unbalanced parentheses in call")


def transform_block_text(text: str) -> str:
    result: list[str] = []
    pos = 0

    while pos < len(text):
        match = CALL_START.search(text, pos)
        if not match:
            result.append(text[pos:])
            break

        result.append(text[pos : match.start()])
        module, func = match.group(1), match.group(2)
        open_paren = match.end() - 1
        args, end_pos = extract_call(text, open_paren)

        line_start = text.rfind("\n", 0, match.start()) + 1
        indent = re.match(r"\s*", text[line_start:]).group(0)

        result.append(rewrite_call(module, func, args, indent))
        pos = end_pos

    return "".join(result)


def transform(content: str) -> str:
    lines = content.splitlines(keepends=True)
    i = 0

    while i < len(lines):
        if not ASSERT_RAISE_START.search(lines[i]):
            i += 1
            continue

        block_end = find_matching_end(lines, i)
        block_text = "".join(lines[i + 1 : block_end])
        transformed = transform_block_text(block_text)

        if transformed != block_text:
            new_lines = transformed.splitlines(keepends=True)
            if new_lines and not new_lines[-1].endswith("\n"):
                new_lines[-1] += "\n"
            lines[i + 1 : block_end] = new_lines

        i = block_end + 1

    return "".join(lines)


def main(argv: list[str]) -> int:
    paths: list[Path] = []

    for arg in argv[1:]:
        path = Path(arg)
        if path.is_dir():
            paths.extend(sorted(path.rglob("*_test.exs")))
        else:
            paths.append(path)

    if not paths:
        paths = sorted(Path("test").rglob("*_test.exs"))

    changed = 0

    for path in paths:
        original = path.read_text()
        updated = transform(original)
        if updated != original:
            path.write_text(updated)
            print(path)
            changed += 1

    print(f"updated {changed} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
