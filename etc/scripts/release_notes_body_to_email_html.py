#!/usr/bin/env python3
"""GitHub-ish release Markdown -> HTML fragment for multipart email bodies.

stdin: changelog markdown only (GitHub release body).
argv[1]: owner/repo (e.g. young-scandinavians/ysc-redesign-ex)
stdout: UTF-8 HTML fragment: one or more <p>…</p> with working links.

Pipeline: extract [label](url) into placeholders, html.escape remainder, link
bare https?:// in prose, link PR # / #N, restore Markdown links, paragraphize.
"""

from __future__ import annotations

import html
import re
import sys


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
        suffix = original[len(enc):]
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
        return "PR " + (
            f'<a href="{html.escape(u, quote=True)}">#{n}</a>'
        )

    s = re.sub(r"(?i)\bPR\s+#(\d{1,10})\b", repl_pr, s)

    def lone(m: re.Match[str]) -> str:
        prefix = m.group(1)
        n = m.group(2)
        u = gh_pull(repo, n)
        return prefix + (
            f'<a href="{html.escape(u, quote=True)}">#{n}</a>'
        )

    # Lone #N only at line start / after whitespace or '(' — skips ">#502" inside anchors.
    return re.sub(r"(^|[\s(])#(\d{1,10})\b", lone, s)


def paragraphize(s: str) -> str:

    chunks = [c for c in re.split(r"\n\s*\n+", s.strip("\n")) if c.strip()]
    out: list[str] = []

    for c in chunks:
        inner_lines = "\n<br/>\n".join(line.strip("\n") for line in c.split("\n"))
        out.append(f"<p>{inner_lines}</p>")

    return "\n".join(out)


def changelog_to_fragment(repo: str, raw: str) -> str:
    raw = raw.strip("\n")
    if not raw:
        return ""

    s, md_store = markdown_link_placeholders(raw)
    s = html.escape(s, quote=False)
    s = link_plain_https(s)
    s = link_pr_styles(repo, s)
    s = restore_md(md_store, s)
    return paragraphize(s)


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
        '<html lang="en"><head><meta charset="utf-8"/></head>'
        "<body>"
        f"<p>{intro_h}</p>"
        f"{fragment}"
        "<hr/>"
        f'<p><a href="{href_q}">GitHub release</a></p>'
        "</body>"
        "</html>"
    )


def main() -> None:
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
