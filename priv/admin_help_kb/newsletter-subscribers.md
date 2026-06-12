---
title: Newsletter subscribers
summary: Subscriber statuses and sources, searching and filtering, adding subscribers manually, removing and re-adding, email validation rules, and automatic bounce handling.
---

# Newsletter subscribers

Found on `/admin/newsletters` under the **Subscribers** tab (`?tab=subscribers`).

## Statuses

- Subscribers are **Active** or **Inactive**. Only active subscribers receive newsletters.
- The header shows the active subscriber count ("{n} subscriber(s)") — this is the audience size for the next send.
- Inactive means the person unsubscribed, was removed by an admin, or was auto-unsubscribed after a hard bounce. Inactive entries stay in the list so they can be re-added.

## Sources

Every subscriber records how they joined:

- `public_signup` — the subscribe form on the public website (including the newsletter archive pages).
- `user_settings` — a member enabled the newsletter in their account settings.
- `user_registration_linked` — linked automatically during account registration.
- `admin_added` — added manually by an admin/volunteer from this tab.
- `hard_bounce` — set when a hard bounce auto-unsubscribed the address (these are inactive).

## Searching and filtering

- Search by email ("Search by email...").
- Status filter: **All**, **Active**, **Inactive**.
- Columns include email, name (when known), status badge, source, and signup date.

## Adding a subscriber

- Click **Add subscriber**, enter the email (placeholder "email@example.com"), and press **Add**. The entry is recorded with source `admin_added`.
- Validation on add/subscribe:
  - Malformed addresses are rejected (invalid email).
  - Domains with no MX records are rejected (cannot receive mail).
  - Disposable/throwaway email domains are blocked against a known list.
  - If the MX lookup itself fails (network), the signup is allowed (fail-open).
- Only add people who explicitly asked to receive the newsletter — unsolicited adds hurt the club's sender reputation.

## Removing and re-adding

- **Remove** unsubscribes the address (confirmation: "Remove this subscriber? They will no longer receive newsletters."). Takes effect from the next send.
- **Re-add** reactivates an inactive subscriber — for people who unsubscribed by accident or changed their mind (always with their consent).

## Automatic behavior

- Every newsletter includes an unsubscribe link; using it marks the subscriber inactive automatically — no admin action needed.
- Hard bounces (permanently undeliverable addresses) automatically unsubscribe the address and set source `hard_bounce`.
