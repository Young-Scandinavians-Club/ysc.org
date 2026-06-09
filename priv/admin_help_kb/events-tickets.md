---
title: Events — tickets, capacity, reservations
summary: Event capacity rules, ticket tier types (free/paid/donation), quantities and sales windows, requires-registration, Tickets TBD, reservations, and tier deletion rules.
---

# Events — tickets and capacity

Found on the **Tickets** tab of the event editor. The whole tab is disabled when the event uses a Partiful link (label: "Tickets (Disabled - Using Partiful)") — built-in ticketing and Partiful are mutually exclusive.

## Event capacity

- **Event Capacity** offers an "Unlimited capacity" checkbox or a **Maximum Attendees** number (minimum 1).
- Leaving max attendees empty/0 means no global cap — only per-tier quantity limits apply.
- Capacity is the hard ceiling across all tiers combined; sales stop when either the event capacity or a tier's quantity runs out.
- The events list shows capacity/registration info in the Registrations column.

## Ticket tiers

- Tier types: **free**, **paid**, **donation**.
  - **Free** tiers are forced to $0.00 — RSVP only, no payment.
  - **Paid** tiers require a fixed price; payment is collected by card at checkout (Stripe).
  - **Donation** tiers have no fixed price — the UI shows "User sets amount" and the attendee chooses what to pay.
- One event can mix tiers, e.g. "Member — free" + "Guest — $20", or early-bird and regular paid tiers.
- **Quantity**: empty or 0 means unlimited (shown as ∞); negative values are invalid.
- **Sales Period**: optional start and end date per tier; the end must be after the start. Use it for early-bird windows or to close sales before catering counts are due.
- **Requires registration** (per-tier toggle): collects each attendee's details at checkout, so you know exactly who is coming.

## Tickets TBD ("Tickets Coming Soon")

- When the event has no tiers, a **Tickets Coming Soon** toggle lets you publish the event with "tickets to be announced".
- It clears automatically the moment the first real tier is added.
- Use it to announce an event before pricing is final.

## Reservations

- Admins can reserve tickets in a tier for a specific member without payment — for comp tickets, performers, or board holds.
- Non-donation tiers show "{n} reserved" when reservations exist; the tier row expands to show active and expired reservation details.
- Reservations count against capacity and can be cancelled to release the seats.

## Monitoring and deletion rules

- Each tier shows its sold count (and reserved count) so uptake is visible at a glance.
- Deleting a tier asks "Are you sure you want to delete this ticket tier? This cannot be undone."
- A tier with sold tickets **cannot be deleted** — the button is disabled and the server rejects it ("Cannot delete ticket tier with sold tickets"). Edit the tier or end its sales window instead.

## Common troubleshooting

- "Members say they can't buy tickets" → check the tier's sales window dates, the tier quantity, and the event capacity.
- "Tickets tab is greyed out" → remove the Partiful link on the Details tab.
- "Need to hold seats" → use a reservation, not a manual purchase.
