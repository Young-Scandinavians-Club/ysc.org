---
title: Newsletters (compose, send, schedule, stats)
summary: Edition statuses, the compose editor and autosave, subject line rules, post/event pickers, test sends, send now, scheduling with timezones, engagement stats, and the public archive.
---

# Newsletters

Admin pages: `/admin/newsletters` (list with Editions, Subscribers, and Saved notices tabs), `/admin/newsletters/new`, `/admin/newsletters/:id/edit`. Public archive: `/newsletters` and `/newsletters/:id`.

## Edition statuses

- An edition is **Draft**, **Scheduled**, **Sending**, or **Sent**.
- Sent editions are **read-only** — the editor shows the banner "Newsletter sent — editing is disabled". There is no unsend.
- Draft and scheduled editions can be deleted (confirmation: "Delete this newsletter? This cannot be undone."). Sent editions cannot be deleted ("Sent newsletters cannot be deleted.").
- **Duplicate** (list row actions, and on sent editions in the editor) creates a new draft with the same title (plus " (copy)"), subject, intro, cover, posts, and events. Schedule/send/archive data is not copied.

## Compose editor

- Desktop layout is split: editor on the left, a live preview of the real email on the right. On mobile, switch between Editor and Preview tabs.
- Pieces of an edition: **cover photo** (from the media library), **headline/title** (max 255 chars), **email subject** (max 255 chars), **intro** (rich-text, up to 50,000 chars), and selected **posts** and **events**.
- New editions auto-create with placeholder title "Untitled" and subject "Newsletter".
- Autosave: 2 seconds after changes (form fields, picker toggles, cover image, intro). The sticky bar shows "Saving…" then "Saved {time}". Title/subject debounce at 600 ms, intro at 800 ms.
- **Insert saved notice** (bookmark button in the intro Trix toolbar) opens a picker. Pick an existing notice to insert at the cursor, or use **New notice** to create one and insert it immediately. Notices are also managed on the Saved notices tab.
- **Save selection as notice** (document button next to it): select text in the intro, click the button, name the notice, and save. The selection is copied into the library (the intro text itself is unchanged).

## Saved notices

- Tab on `/admin/newsletters?tab=notices`: create, edit, and delete named rich-text snippets.
- Inserting a notice copies its HTML into the current intro; later edits to the library do not change editions that already inserted it.

## Subject line

- A character counter shows "{n} / 60 characters" under the **Email subject line** field and turns amber past 60 characters — that's advisory (the hard limit is 255), because longer subjects get truncated in many email clients, especially on phones.
- Subject and headline are independent: subject is the inbox line, headline is the big title inside the email.

## Post and event pickers

- Two picker sections: **Latest news (posts)** — the 50 most recent published posts — and **Upcoming events** — the next 50 upcoming events.
- The UI shows 10 items initially with a "Show more ({n} remaining)" button revealing 10 more per click.
- Click a card to include it; click again to remove. **Selection order is preserved** and shown with numbered badges — the order you click is the order in the email.
- There is no hard cap on how many items can be selected.
- Drafts never appear in the pickers — publish a post first if it should be featured.

## Test send

- **Send test** delivers a real copy to the current admin's own email, with the subject prefixed "[YSC] [TEST]".
- Test sends don't change the edition's status or counters; send as many as needed.
- Success toast: "Test email sent to {email}."

## Send now

- **Send now** (in the sticky bar, and in the list's dropdown) opens a confirmation: "Send this newsletter to all subscribers now? This cannot be undone."
- The draft is saved first; if that fails you'll see "Save the draft first, then send."
- On confirm: status becomes **sending**, a background job delivers to **all active subscribers**, and the toast "Sending newsletter…" appears. When delivery completes, the list updates live with "\"{title}\" has been sent."
- After sending, the edition becomes permanently read-only and is archived publicly.

## Scheduling

- **Schedule** opens a "Schedule newsletter" modal with a **Send at** date-time field.
- The browser's timezone is auto-detected and the chosen time is converted to UTC for storage; the scheduled indicator shows the time in UTC.
- Scheduled editions remain **fully editable until they send**.
- Pressing Send now on a scheduled edition sends immediately (the old scheduled job is skipped once the edition is sent).
- Success toast: "Newsletter scheduled."

## Stats (sent editions)

- The editor for a sent edition shows: **Sent at**, **Emails sent**, **Unique opens** and **Unique clickers** (distinct recipients, with percentage of sent), **Bounces**, **Unsubscribe link clicks** (historical; people who clicked the unsubscribe URL), and **Confirmed unsubscribes** (people who completed unsubscribe from that edition's email link).
- A **Clicks by link** breakdown shows which links were clicked, labeled as the matching Event or Post when recognizable. Unsubscribe URLs are excluded from this list and shown in the unsubscribe metrics above.
- Data comes from the email provider's events (send, delivery, open, click, bounce, complaint) and accumulates over hours and days after sending. Confirmed unsubscribes are recorded when a recipient finishes the unsubscribe flow from an edition email.

## Public archive

- Sent editions are published on the public site at /newsletters using a de-personalized archived copy of the HTML.
- Archive pages include a guest subscribe form (bot-protected and rate-limited).

## Editions list

- Search "Search by title...", filter by **Status** (Draft / Scheduled / Sent), **Creator**, and **Date Created** range. 20 per page by default.

## Permissions

- Newsletter pages are available to both volunteers and admins.
