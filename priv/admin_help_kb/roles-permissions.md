---
title: Roles & permissions (volunteer vs admin)
summary: Exactly what volunteers can and cannot do compared to full admins, which sidebar areas and routes each role sees, and special board-position-based access.
---

# Roles and permissions

There are two staff roles in the admin area: **volunteer** and **admin** (full admin). Both can access `/admin`, but they see different sidebars, dashboards, and have different permissions.

## What volunteers can do

- **Posts**: create, edit, and publish news articles (full access; deleting uses the soft-delete update flow).
- **Events**: reach the event admin pages — create, edit, publish, and manage tickets in practice.
- **Newsletters**: compose, send, schedule, and manage subscribers (no separate restriction).
- **Media**: browse and view the library. Note: the authorization policy reserves image create/update/delete for admins, so volunteers may hit authorization errors on uploads/edits.
- **Day-of tools**: event check-in desk, QR scanner sessions, and membership check-in desks.
- **Dashboard**: a volunteer-tailored overview (see dashboard document).
- **Own data**: read and update their own user profile and bookings, like any member.

## What only full admins can do

These areas use a stricter pipeline and are unreachable for volunteers (volunteers get redirected):

- **Users** — member management, applications review, roles.
- **Memberships** — membership management (membership-director board position grants the nav item).
- **Bookings** — cabin booking management and booking entitlements.
- **Money** — payments, refunds, payouts, ledger (treasurer board position grants the nav item).
- **Settings** — site settings.
- **Impersonation**, LiveDashboard metrics, Google Photos integration.

## Sidebar visibility

- **Volunteers see:** Overview, Posts, Events, Newsletters, Media, Help.
- **Admins additionally see:** Bookings, Users, Memberships (with the membership-director position), Money (with the treasurer position), Settings.

## Comments

- Anyone can create/read comments; admins can edit/delete any comment, others only their own.

## Practical guidance

- If a page redirects a volunteer back to the dashboard, it is admin-only by design.
- Roles are assigned by an existing admin from user management; contact the board for role changes.
- When a volunteer needs something from a restricted area (refund, member lookup, settings change), ask a board member / full admin.
