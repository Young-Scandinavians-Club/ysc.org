#!/usr/bin/env python3
"""GitHub-ish release Markdown -> HTML fragment for multipart email bodies.

stdin: changelog markdown only (GitHub release body).
argv[1]: owner/repo (e.g. young-scandinavians/ysc-redesign-ex)
stdout: UTF-8 HTML fragment with headings, lists, and links.

Pipeline: parse Markdown blocks, apply inline formatting (bold, code, links),
emit email-friendly semantic HTML.
"""

from __future__ import annotations

import html
import re
import sys
from typing import Literal

Block = tuple[
    Literal["heading"],
    int,
    str,
] | tuple[
    Literal["paragraph"],
    str,
] | tuple[
    Literal["list"],
    list[tuple[int, str]],
] | tuple[
    Literal["hr"],
]

HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
LIST_RE = re.compile(r"^(\s*)([-*])\s+(.+)$")
HR_RE = re.compile(r"^---+\s*$")

EMAIL_STYLES = """
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  font-size: 15px;
  line-height: 1.5;
  color: #1a1a1a;
  margin: 0;
  padding: 0;
}
h2 {
  font-size: 18px;
  font-weight: 600;
  margin: 24px 0 8px;
  color: #111;
}
h3 {
  font-size: 16px;
  font-weight: 600;
  margin: 16px 0 6px;
  color: #222;
}
p {
  margin: 0 0 12px;
}
ul {
  margin: 0 0 12px;
  padding-left: 24px;
}
li {
  margin: 4px 0;
}
strong {
  font-weight: 600;
}
code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 13px;
  background: #f3f4f6;
  padding: 1px 4px;
  border-radius: 3px;
}
a {
  color: #0969da;
  text-decoration: none;
}
hr {
  border: none;
  border-top: 1px solid #d0d7de;
  margin: 20px 0;
}
""".strip()


def gh_pull(repo: str, num: str) -> str:
    return f"https://github.com/{repo}/pull/{num}"


def markdown_link_placeholders(
    raw: str,
) -> tuple[str, list[tuple[str, str]]]:
    store: list[tuple[str, str]] = []

    def repl(m: re.Match[str]) -> str:
        store.append((m.group(1), m.group(2)))
        return f"\x00md{len(store) - 1}\x00"

    s = re.sub(r"\[([^\]\r\n]+)\]\((https?://[^)\s]+)\)", repl, raw)
    return s, store


def restore_md(store: list[tuple[str, str]], s: str) -> str:
    out = s

    for i, (lab, url) in enumerate(store):
        token = f"\x00md{i}\x00"
        hu = html.escape(url.strip(), quote=True)
        hl = html.escape(lab.strip(), quote=False)
        out = out.replace(token, f'<a href="{hu}">{hl}</a>')

    return out


def link_plain_https(s: str) -> str:
    """Wrap http(s) URLs in prose. Caller must run on html.escaped plaintext so callers
    may pass escaped ``&amp;`` in URLs; we unescape once for the real href/display.
    """

    def repl(m: re.Match[str]) -> str:
        original = m.group(1)
        enc = original.rstrip(").,;:\"]")
        suffix = original[len(enc) :]
        raw_u = html.unescape(enc)

        anchor = (
            f'<a href="{html.escape(raw_u, quote=True)}">'
            f"{html.escape(raw_u)}"
            f"</a>"
        )
        return anchor + html.escape(suffix)

    return re.sub(r"\b(https?://\S+)", repl, s)


def link_pr_styles(repo: str, s: str) -> str:
    def repl_pr(m: re.Match[str]) -> str:
        n = m.group(1)
        u = gh_pull(repo, n)
        return "PR " + (f'<a href="{html.escape(u, quote=True)}">#{n}</a>')

    s = re.sub(r"(?i)\bPR\s+#(\d{1,10})\b", repl_pr, s)

    def lone(m: re.Match[str]) -> str:
        prefix = m.group(1)
        n = m.group(2)
        u = gh_pull(repo, n)
        return prefix + (f'<a href="{html.escape(u, quote=True)}">#{n}</a>')

    # Lone #N only at line start / after whitespace or '(' — skips ">#502" inside anchors.
    return re.sub(r"(^|[\s(])#(\d{1,10})\b", lone, s)


def format_inline(repo: str, text: str) -> str:
    s, md_store = markdown_link_placeholders(text)
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = link_plain_https(s)
    s = link_pr_styles(repo, s)
    return restore_md(md_store, s)


def _indent_width(prefix: str) -> int:
    return len(prefix.replace("\t", "    "))


def parse_blocks(raw: str) -> list[Block]:
    lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    blocks: list[Block] = []
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        heading = HEADING_RE.match(stripped)
        if heading:
            level = min(len(heading.group(1)), 6)
            blocks.append(("heading", level, heading.group(2).strip()))
            i += 1
            continue

        if HR_RE.match(stripped):
            blocks.append(("hr",))
            i += 1
            continue

        list_match = LIST_RE.match(line)
        if list_match:
            items: list[tuple[int, str]] = []
            while i < len(lines):
                match = LIST_RE.match(lines[i])
                if not match:
                    break
                items.append((_indent_width(match.group(1)), match.group(3).strip()))
                i += 1
            blocks.append(("list", items))
            continue

        paragraph_lines: list[str] = []
        while i < len(lines):
            current = lines[i]
            current_stripped = current.strip()
            if not current_stripped:
                break
            if (
                HEADING_RE.match(current_stripped)
                or HR_RE.match(current_stripped)
                or LIST_RE.match(current)
            ):
                break
            paragraph_lines.append(current_stripped)
            i += 1

        blocks.append(("paragraph", " ".join(paragraph_lines)))

    return blocks


def render_list(items: list[tuple[int, str]], repo: str) -> str:
    if not items:
        return ""

    def walk(pos: int, indent: int) -> tuple[str, int]:
        chunks = ["<ul>"]
        while pos < len(items):
            item_indent, text = items[pos]
            if item_indent < indent:
                break
            if item_indent > indent:
                break

            pos += 1
            child_html = ""
            if pos < len(items) and items[pos][0] > indent:
                child_html, pos = walk(pos, items[pos][0])

            chunks.append(f"<li>{format_inline(repo, text)}{child_html}</li>")

        chunks.append("</ul>")
        return "".join(chunks), pos

    html_out, _ = walk(0, items[0][0])
    return html_out


def render_blocks(repo: str, blocks: list[Block]) -> str:
    parts: list[str] = []

    for block in blocks:
        kind = block[0]

        if kind == "heading":
            _, level, text = block
            tag = "h2" if level <= 2 else "h3"
            parts.append(f"<{tag}>{format_inline(repo, text)}</{tag}>")
        elif kind == "paragraph":
            _, text = block
            parts.append(f"<p>{format_inline(repo, text)}</p>")
        elif kind == "list":
            _, items = block
            parts.append(render_list(items, repo))
        elif kind == "hr":
            parts.append("<hr/>")

    return "\n".join(parts)


def changelog_to_fragment(repo: str, raw: str) -> str:
    raw = raw.strip("\n")
    if not raw:
        return ""

    return render_blocks(repo, parse_blocks(raw))


def build_committee_release_email_html(
    repo: str,
    intro_plain: str,
    changelog_md: str,
    release_url: str,
) -> str:
    fragment = changelog_to_fragment(repo, changelog_md.strip()).strip()

    if not fragment:
        fragment = "<p><em>(No release body.)</em></p>"

    intro_h = html.escape(intro_plain, quote=False)
    href_q = html.escape(release_url, quote=True)

    return (
        "<!DOCTYPE html>\n"
        '<html lang="en"><head><meta charset="utf-8"/>'
        f"<style>{EMAIL_STYLES}</style></head>"
        "<body>"
        f"<p>{intro_h}</p>"
        f"{fragment}"
        "<hr/>"
        f'<p><a href="{href_q}">GitHub release</a></p>'
        "</body>"
        "</html>"
    )


def _self_test() -> None:
    sample = """\
This release focuses on critical correctness fixes.

## Highlights

- **Payment Integrity:** Hardened checkout to prevent double-charges ([#676](https://github.com/org/repo/pull/676)).
- **Admin Performance:** Deferred loading for admin pages.

## Added

- **SEO & Social Sharing**
    - Implemented Open Graph metadata #687.
    - Added canonical URL redirects #686.

## Fixed

- Blocked repricing when payment is in flight #683.
"""

    out = changelog_to_fragment("org/repo", sample)
    assert "<h2>" in out
    assert "<ul>" in out
    assert "<li>" in out
    assert "<strong>Payment Integrity:</strong>" in out
    assert 'href="https://github.com/org/repo/pull/676"' in out
    assert 'href="https://github.com/org/repo/pull/687"' in out
    assert "<br" not in out
    assert "## Highlights" not in out


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        _self_test()
        return

    if len(sys.argv) < 2:
        sys.stderr.write(
            "Usage: python3 release_notes_body_to_email_html.py owner/repo < body.md\n",
        )
        sys.exit(2)

    repo = sys.argv[1]
    blob = sys.stdin.read()
    print(changelog_to_fragment(repo, blob), end="")


if __name__ == "__main__":
    main()
