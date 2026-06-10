# Admin & volunteer help guides

Interactive step-by-step guides live in the app at **`/admin/help`** (auth required). Source content is defined in Elixir modules under `lib/ysc_web/admin_help/guides.ex`.

## Guide inventory

| Slug | Title |
|------|-------|
| `getting-started` | Getting started in Admin |
| `posts/publish` | Publish a news article |
| `posts/pin-and-drafts` | Pin posts and manage drafts |
| `newsletters/compose` | Compose a newsletter |
| `newsletters/send` | Send or schedule a newsletter |
| `newsletters/subscribers` | Manage newsletter subscribers |
| `events/create` | Create an event |
| `events/tickets` | Event tickets and capacity |
| `events/publish` | Publish or schedule an event |
| `events/updates` | Email event attendees |
| `media/upload` | Upload and use images |
| `day-of/check-in` | Event check-in desk |
| `day-of/scanner` | QR scanner |

## Adding a guide

1. Add a module under `YscWeb.AdminHelp.Guides` implementing `YscWeb.AdminHelp.Guide`.
2. Register it in `YscWeb.AdminHelp.Registry.@guides`.
3. Register a ghost preview slug in `YscWeb.AdminHelp.Ghost.Registry` and add a scene in `Ghost.Previews` (see Illustrations below).
4. Optional: `faq/0` and `troubleshooting/0` for the LLM step clarifier.
5. Add `admin_help_link` on the relevant admin LiveView.

## Illustrations & hotspots

Guide steps use **ghost previews** — live renderings of the real admin UI at
`/admin/help/ghost/{slug}?embed=1`, embedded in the wizard via iframe. Real
chrome (sidebar, page titles, button labels, tabs) stays literal; dynamic
content (table rows, editor body, thumbnails, stats) is replaced with shimmering
skeleton bars (`YscWeb.AdminGhostComponents`).

1. In `guides.ex`, set `image: "ghost:posts-list"` (slug must be in `Ghost.Registry`).
2. Add or extend a scene in `lib/ysc_web/admin_help/ghost/previews.ex` using the
   same layout components as the real admin page (`side_menu`, `<.button>`,
   `<.admin_page_title>`, etc.).
3. Preview locally: `http://localhost:4000/admin/help/ghost/posts-list?embed=1`
4. Hotspot coordinates are **percentages** (`x`, `y`, `w`, `h`) of the 1280×800
   embed viewport. Each hotspot can define separate `expanded:` and `collapsed:`
   layouts (sidebar open vs collapsed); omit `collapsed:` to reuse `expanded:`.
   Shorthand `%{x, y, w, h, label}` sets both. Toggle the sidebar in a guide to
   tune each layout. Set `style: :hint` for a light dashed frame (good on large
   public previews); default is `:highlight`. Long ghost pages can set
   `image_scroll` / `public_image_scroll` on a step to an element id from
   `ghost/previews.ex` (e.g. `ghost-event-agenda-section`) so the iframe frames
   the right section. See `YscWeb.AdminHelp.Hotspot`.
5. **Print / PDF** still uses static images from `priv/static/images/admin-help/`
   (`.svg` or `.png` if captured). Run `etc/scripts/capture_admin_help_ghosts.sh`
   (dev server on port 4000) to refresh PNGs from the ghost pages.

## OpenRouter (optional)

Guide finder and step clarifier require:

```bash
OPENROUTER_API_KEY=sk-or-...
OPENROUTER_MODEL=google/gemma-3-27b-it   # optional
```

Without `OPENROUTER_API_KEY`, wizards work normally; LLM panels are hidden.

Rate limit: 10 requests per 10 minutes per user (`Ysc.AdminHelpRateLimit`).

## Knowledge base (LLM grounding)

Detailed reference docs live in **`priv/admin_help_kb/*.md`** and are loaded by
the assistant **on the fly**: the model only sees a one-line-per-doc index
(slug, title, summary) in its system prompt, and may reply with
`{"read_docs": ["slug", ...]}` (max 3) to have full documents injected into a
follow-up turn before answering. Large reference content therefore never enters
the context window unless it's relevant. See `Ysc.AdminHelp.KnowledgeBase` and
the retrieval loop in `Ysc.AdminHelp.Assistant`.

Each file needs front matter:

```markdown
---
title: Posts & news articles
summary: One line shown to the model in the index.
---

# Body in markdown…
```

Conventions:

- Filename (without `.md`) is the slug; only `[a-z0-9-]` (path traversal is rejected).
- Be exhaustive and concrete: exact button labels, limits, state names, side
  effects (e.g. "publishing an event emails members"). The model is told to
  answer only from guides + these docs.
- Keep one feature area per file so retrieval stays targeted.
- Update the relevant doc whenever admin UI behavior changes — the assistant's
  accuracy depends on it.

Current docs: `posts`, `newsletters`, `newsletter-subscribers`,
`events-details`, `events-tickets`, `events-publishing`, `events-updates`,
`media`, `check-in`, `scanner`, `roles-permissions`, `dashboard`.

### Live data snapshots

The same `read_docs` mechanism also serves **real database examples** via
`Ysc.AdminHelp.LiveExamples` (slugs prefixed `live-`): `live-recent-posts`,
`live-recent-events`, `live-recent-newsletters`. Each is an allowlisted,
read-only snapshot capped at 10 rows exposing only titles, states, dates, and
counts — never member names, emails, or other personal data. The model is told
to request these when a question concerns actual site content ("why isn't my
event visible?", "show me an example subject line we've used").

## Printing / PDF

Each guide includes a **Print / Save PDF** button (the index can still be
printed via the browser's print dialog). Printing uses a dedicated layout that:

- Includes **all steps** (not just the current wizard step)
- Shows a cover, table of contents, screenshots with numbered callouts, FAQ, and troubleshooting
- Hides the admin sidebar, navigation, and interactive controls

Use your browser’s print dialog and choose **Save as PDF** to share via email.

## Tests

```bash
mix test test/ysc_web/admin_help/
mix test test/ysc_web/live/admin/admin_help_live_test.exs
mix test test/ysc/admin_help/
```
