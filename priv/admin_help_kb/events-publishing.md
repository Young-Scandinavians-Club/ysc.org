---
title: Events — publishing, scheduling, cancelling
summary: Publish requirements and side effects (notification emails, photo collections), scheduled publishing and its timezone, unpublish vs cancel, and deleting events.
---

# Events — publishing and lifecycle actions

All actions live in the event editor header / menu: **Publish**, schedule dropdown, **Unpublish**, **Cancel Event**, **Copy Event**, **Delete Event**, **Check In**.

## Publish requirements

- Publishing requires a non-empty **title** and a **start date**; the event must be in Draft or Scheduled state.
- When blocked, the Publish button's tooltip reads "A title and event date must be set before publishing".
- Best practice before publishing: cover image, summary, location and map pin, complete overview, and tickets configured (or Tickets Coming Soon enabled) — publishing notifies members, so it should be the final step.

## What happens on publish

- The event state becomes **Published** and the published timestamp is set.
- **Member notification emails are scheduled** (a background worker sends them).
- An **event photo collection** is created/ensured, and a photo reminder worker is scheduled so attendees get a reminder to upload photos after the event ends.
- The public event page goes live, the event appears in listings, and ticket sales open according to each tier's sales window.

## Scheduled publishing

- The schedule dropdown opens a "Scheduled At" date-time field with a **Set Schedule** button.
- The chosen time is interpreted in **America/Los_Angeles (Pacific)** time and stored as UTC. The publish time must be **before the event start**.
- The event sits in the **Scheduled** state and a background worker publishes it automatically (it polls every few minutes, so the publish happens within ~5 minutes of the chosen time) — including notifications and ticket sales.
- Scheduled events remain fully editable until they go live. Success toast: "Event scheduled successfully".

## Unpublish vs cancel

- **Unpublish** (published events only) quietly returns the event to **Draft** and clears the published timestamp — the public page disappears. Use for "published too early" mistakes.
- **Cancel Event** (published events only) sets the state to **Cancelled** but keeps the page visible, clearly marked — the right choice once people have registered, so ticket holders see the status.
- Members who already received the publish notification keep that email either way; consider sending an update from the Updates tab to explain a cancellation.

## Deleting

- **Delete Event** soft-deletes (state Deleted) after confirmation. Use for drafts and mistakes; published events with registrations should be cancelled rather than deleted so attendees can still find the status.

## Related

- Copying events (what carries over) is covered in the events-details document.
- Emailing attendees after publish is covered in the events-updates document.
