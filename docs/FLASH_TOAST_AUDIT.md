# Flash toast audit: titles and icons

`YscWeb.Flash` uses `default_icon_opts/2` so that `:info`, `:error`, and `:warning` toasts get a default title ("Success", "Error", "Warning") and icon when no `title:` is passed. LiveToast only renders the icon inside the title block, so **without a title the icon is never shown**. Passing a contextual title improves UX and ensures the icon is clearly associated with the action.

## Summary

- **Toasts without a custom title** rely on the generic "Success" / "Error" / "Warning". Adding a contextual title (e.g. "Event", "Booking", "Payment") makes the toast clearer and reinforces the icon.
- **`:email` toasts** (e.g. in `user_session_controller`) use a custom kind that has no default title/icon; they are used to prefill the email field on the login page, so no icon is required.
- **Custom icons** (beyond success/error/warning) can be added in `core_components.ex` and passed via `icon:` where they add meaning (e.g. payment, booking, document upload).

## Changes made

### Contextual titles added

| File | Message / context | Title added |
|------|-------------------|-------------|
| `event_details_live.ex` | Event not found, Order not found, expired order, registration/checkout errors | "Event", "Order", "Registration", "Checkout" |
| `booking_receipt_live.ex` | Booking not found, refund/cancel success | "Booking" |
| `order_confirmation_live.ex` | Order not found | Already had "Order" |
| `admin_bookings_live.ex` | Blackouts, refunds, pricing, season, refund policy, door code, rooms | "Blackout", "Refund", "Pricing", "Season", "Refund policy", "Door code", "Room" |
| `admin_events_new.ex` | Event deleted/published/draft/cancelled, ticket reservation | "Event", "Tickets" |
| `admin_money_live.ex` | Payment/payout not found, credit, expense report, refund errors | "Payment", "Payout", "Credit", "Expense report" |
| `admin_settings_live.ex` | Job statistics, settings, job reschedule, job not found | "Settings", "Job" |
| `admin_user_detail_page.ex` | User updated, subscription/bank/note errors | Already had "Profile"; added where missing |
| `user_settings_live.ex` | Payment/membership errors without title, email change initiated | "Payment", "Membership", "Email" |
| `user_login_live.ex` | Generic error message | "Login" |
| `user_security_live.ex` | Session already signed out, passkey errors | "Session", "Passkey" |
| `user_registration_live.ex` | Registration success | "Registration" |
| `user_confirmation_live.ex` | User confirmed | "Account" |
| `user_reset_password_live.ex` | Password reset success | "Password" |
| `user_forgot_password_live.ex` | Already had title "Password reset" | — |
| `account_setup_live.ex` | Verification/password/phone/setup errors and success | "Account", "Phone", "Setup" |
| `booking_checkout_live.ex` | Guest information required | "Checkout" |
| `user_booking_detail_live.ex` | Booking not found | "Booking" |
| `family_invite_acceptance_live.ex` | Invalid invitation / not found | "Invitation" |
| `clear_lake_booking_live.ex` | Booking/validation errors | "Booking" |
| `tahoe_booking_live.ex` | Validation errors | "Booking" |
| `volunteer_live.ex` | Application submitted / submit again | "Volunteer" |
| `post_live.ex` | Article not found, comment posted | "Article", "Comment" |
| `ticket_tier_management.ex` | Tier deleted, reservation, TBD, cancellation | "Tickets", "Reservation" |
| `user_session_controller.ex` | `:email` toasts are data-only (prefill); no title/icon needed | — |

### Custom icon recommendations

Existing helpers in `core_components.ex`: `flash_toast_icon_success`, `flash_toast_icon_error`, `flash_toast_icon_warning`, `flash_toast_icon_clock`.

Where a **custom icon** would be appropriate (optional follow-up):

- **Payment / membership**: e.g. `hero-credit-card` or `hero-currency-dollar` for payment/membership toasts.
- **Booking / events**: e.g. `hero-calendar-days` or `hero-ticket` for booking/event/order toasts.
- **Document / upload**: e.g. `hero-document-arrow-up` for expense report uploads.
- **Impersonation**: e.g. `hero-user-circle` for impersonation start/stop (already have good titles).
- **Passkey / security**: e.g. `hero-key` or `hero-finger-print` for passkey/session toasts.

Optional custom icons were added in `core_components.ex`:

- `flash_toast_icon_payment` (hero-credit-card) – use for payment/membership/invoice toasts, e.g. `icon: &YscWeb.CoreComponents.flash_toast_icon_payment/1`
- `flash_toast_icon_calendar` (hero-calendar-days) – use for booking/event/order toasts, e.g. `icon: &YscWeb.CoreComponents.flash_toast_icon_calendar/1`

Pass in toast opts when a contextual icon is desired; the default success/error/warning icons remain for generic toasts.
