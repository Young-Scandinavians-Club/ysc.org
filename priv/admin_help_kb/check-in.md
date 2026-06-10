---
title: Event check-in desk
summary: The day-of check-in desk — search formats (name, email, ORD-, TKT-), order grouping, checking in tickets and whole orders, undo, live multi-device sync, and keyboard shortcuts.
---

# Event check-in desk

Opened via **Check in** on a published/scheduled event (from the events list, the editor, or the dashboard's upcoming-events widget). Shows a sticky header with the event name, a live counter "Checked in: {n} / {total}", a search bar, and the attendee list.

## Search

- Placeholder: "Search by name, email, ORD-xxx, or TKT-xxx…".
- Matches attendee name, purchaser email, order reference (**ORD-**), or ticket reference (**TKT-**). Both references appear in the attendee's confirmation email, so they can just show their phone.
- Search debounces at 300 ms.
- **Escape** clears the search and refocuses the input.

## Attendee list and order grouping

- Only **confirmed** tickets are listed.
- Pending tickets are grouped by order; the group header shows the order reference and ticket count. Multi-ticket orders get a **Check in all** button for when the whole group arrives together.
- Checked-in attendees move to a separate section with strikethrough names.
- Empty states: "No confirmed tickets for this event" and "All attendees checked in!".

## Checking in and undoing

- Click the checkbox on a ticket row to check in one person, or **Check in all** for the order.
- Undo: hover the checkmark (it becomes an X, tooltip "Undo check-in"); on mobile there's an **Undo** button. The ticket returns to pending.
- Manual check-ins are recorded under an auto-created scan session named "Manual Check-in: {event title}", so they show up in session history.

## Live multi-device sync

- The desk subscribes to real-time check-in events: any check-in or undo from another device (another desk, or the QR scanner) updates the list and counter within a second.
- Run multiple phones/laptops at a busy door safely — no double-admitting.

## Keyboard shortcuts

Active when the search box has focus:

- **↑ / ↓** — move the highlight through pending rows.
- **Enter** — check in the highlighted ticket (or the only result).
- **Alt+1 / Alt+2 / Alt+3** — instantly check in the 1st/2nd/3rd pending row on screen.
- **Escape** — clear the search.

The legend under the search bar reads "navigate · ↵ enter check in · alt 1–3 quick check in". Type-a-few-letters-then-Enter is much faster than tapping.

## Related door tools

- **QR Scanner** button — camera-based ticket scanning (see the scanner document).
- **Membership Check-in** button — opens a desk for verifying member cards at the door (an "event + members" session).
