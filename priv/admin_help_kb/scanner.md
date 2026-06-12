---
title: QR scanner & membership check-in
summary: Scan session types (event tickets, membership, event+members), what each scan validates, camera permissions, resuming sessions, the membership desk, CSV export, and past session history.
---

# QR scanner and membership check-in

Pages: `/admin/scanner` (start/resume sessions), `/admin/scanner/sessions` (past sessions), `/admin/scanner/sessions/:id` (session detail), `/admin/membership-check-in/:id` (membership desk).

## Session types

| Type | UI label | Purpose |
|------|----------|---------|
| Membership | **Membership** | Standalone membership verification (e.g. at the cabin) |
| Event | **Event** | Ticket QR check-in for one event |
| Event + Members | **Event + Members** | Membership verification desk tied to an event |

- Start from "Check-in Sessions" → **New Check-in Session**, pick a mode card, select the event for event modes ("Choose an event..."), and press **Start Session**.
- The browser asks for camera permission on first use — allow it (on iPhones use Safari).

## What a scan validates

**Event ticket sessions:**
- The ticket must exist, belong to **this** session's event, be **confirmed**, and not already checked in.
- Wrong event → "This ticket is for a different event."
- Wrong status → "This ticket is {status}, not confirmed."
- Already checked in → flagged as already scanned; if the order has other unchecked tickets, the scanner prompts to check in the remaining ones.
- Membership QR codes are rejected in ticket mode ("Invalid Ticket: This is a Membership QR. Please scan an Event Ticket.").

**Membership sessions:**
- Validates the member's QR token and records membership status (active/inactive) and plan type.
- Ticket QRs are rejected with a clear message.

**Event + Members desk:**
- Membership scans verify an active membership and auto check-in when active.

Attendees get their QR codes in the ticket confirmation email (and wallet pass if added). Glare or cracked screens are the usual scan failures — raise screen brightness, or fall back to the check-in desk search (name/ORD-).

## Resuming sessions

- Sessions stay open if the phone locks or the browser closes. The scanner page shows open sessions with a **Resume** link (Membership and Event types) — Event + Members sessions use **Open Desk** instead.
- Only the **session creator** can resume their session ("You can only resume scan sessions you created.").
- Resuming a closed session shows "That session is already closed."
- You can resume on a different device — open the scanner page there and resume.

## Membership desk features

- Search members by name or email; active members get a **Check In** button, inactive show "No active membership — cannot be checked in".
- Already-checked-in members show a **Checked In** badge with **Undo**.
- **Share** copies the desk URL so other admins can run the same desk; live sync keeps all devices consistent.
- **Complete** locks the session ("Complete this session? It will be locked...") and enables **Export CSV**.
- Keyboard: Alt+1–3 quick check-in on search results.

## Past sessions

- "Check-in Sessions" lists all sessions (Active/Closed badges) with event, creator, and time.
- Session detail shows every scan: name, email, time, status/type, and a result badge, with **Export CSV**.
- Useful for the morning after: attendance numbers, rush timing, or auditing a disputed check-in.

## Scans sync with the check-in desk

Every successful scan also updates the event check-in desk live — desk staff see scanner check-ins in real time.
