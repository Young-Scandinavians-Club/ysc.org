---
title: Events — details, agenda, hosts, copying
summary: Event states and editor tabs, field limits, Partiful links, dates and location, the overview editor, agendas, hosts, copying events, and the events list.
---

# Events — details tab

Admin pages: `/admin/events` (list), `/admin/events/new` (creates a draft immediately), `/admin/events/:id` (editor). The editor has three tabs: **Event Details**, **Tickets**, **Updates**.

## States

- An event is **Draft**, **Scheduled** (queued to auto-publish), **Published**, **Cancelled**, or **Deleted** (soft delete).
- Clicking **New Event** creates a draft titled "New Event" instantly and opens the editor. Drafts are invisible to members.
- The list has tabs **Upcoming**, **Drafts**, **Past**, **All**, plus a state filter (Published / Draft / Scheduled / Cancelled). Scheduled events show a badge with tooltip "Publishes on {date}".

## Core fields and limits

- **Event Title** — required, max 100 characters.
- **Summary** — max 200 characters with a live "{n}/200" counter; HTML is stripped. This is the teaser shown on event cards across the site and in newsletters.
- **Cover image** — picked from the shared media library; headlines the public page, listings, and newsletter cards.
- **Dates** — single day or a multi-day range, with start and end times.
- **Location** — address text plus a map pin that powers the map and directions on the public page.

## Partiful link (external registration)

- Optional field "Partiful Link (Optional)" (placeholder `https://partiful.com/e/...`). It must be a partiful.com URL.
- Partiful and built-in ticketing are **mutually exclusive**:
  - The Partiful field is disabled once the event has any ticket tiers, with the warning "Partiful cannot be used when this event has ticket tiers...".
  - With a Partiful link set, the Tickets tab is labeled "Tickets (Disabled - Using Partiful)" and shows an "External Registration via Partiful" panel instead of tier editing.
- With Partiful, the public page sends attendees to Partiful to register; the built-in check-in tools won't have ticket data.

## Overview (description)

- The full description is written in a rich-text editor — headings, lists, links, and inline images from the media library.
- Good overviews cover: what's included, what to bring, parking/transit, guest policy, and food arrangements.

## Hosts

- The **Hosts** section searches members by name or email; **Add** / **Remove** as needed.
- Hosts are displayed on the public event page. Note: hosts are **not** carried over when copying an event.

## Agenda

- The **Agenda** section (button "Add Agenda") supports one or more agenda sections, each with a title and ordered items.
- Each agenda item has a title, description, and start/end time. Items and sections can be reordered and deleted.
- The agenda renders as a timeline on the public event page.

## Copying an event

- **Copy Event** (in the editor menu, or **Copy** in the list's row actions; confirmation "Copy this event?") creates a new **draft** titled "Copy of {original title}".
- Copied: agendas and items, ticket tiers, FAQ entries, cover image, location, dates, Partiful link, capacity, and details.
- NOT copied: hosts, tickets/orders/registrations, publish timestamps.
- Always update the dates on the copy before publishing. Copying is the fastest way to set up recurring events.

## Events list

- Header buttons: **Check-in & Scan** and **New Event**.
- Search "Search by event name...", filters for State, Organizer, and Event Date Range.
- Row actions: **View live**, **Copy**, **Edit**, and **Check in** (published/scheduled events only).
- Events use EVT- reference IDs; tickets are TKT- and orders ORD-.

## Permissions note

- Event admin pages are reachable by both volunteers and admins.
