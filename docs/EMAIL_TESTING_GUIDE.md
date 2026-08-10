# Email & SMS notification previews

How to review email and SMS templates in development, keep sample data in sync, and what CI posts on PRs.

## Quick start

With `make dev` running:

| What | URL |
|------|-----|
| **Template catalog** (all emails + SMS with sample data) | http://localhost:4000/dev/notifications |
| **Swoosh mailbox** (emails actually sent by the app) | http://localhost:4000/dev/mailbox |
| Single email HTML | http://localhost:4000/dev/preview-email/`template_name` |

These routes exist only when `config :ysc, dev_routes: true` (default in `config/dev.exs`).

## Two ways to preview

### 1. Notification catalog (design review)

Use this when you want to **see every template** without walking through app flows.

1. Open http://localhost:4000/dev/notifications
2. Use the **Emails** / **SMS** tabs in the sidebar
3. Click a template name — emails load in an iframe; SMS show in a phone-style bubble
4. Optional: **Open HTML** / **Send to mailbox** in the header for the selected email

Selection is shareable, e.g.  
`/dev/notifications?type=email&name=membership_ended`

### 2. Swoosh mailbox (integration testing)

Use this when you want to verify **real send paths** (Oban workers, preferences, subjects, etc.).

1. Trigger a flow (register, reset password, buy a ticket, …)
2. Open http://localhost:4000/dev/mailbox
3. Emails are in memory and clear when the server restarts

```
App → Notifier / worker → Swoosh Local adapter → /dev/mailbox
```

## Sample data

Previews use defaults from:

[`priv/dev/notification_preview_samples.exs`](../priv/dev/notification_preview_samples.exs)

Structure:

```elixir
%{
  emails: %{
    "membership_ended" => %{first_name: "Astrid", end_date: "...", ...},
    ...
  },
  sms: %{
    "booking_checkin_reminder" => %{...},
    ...
  },
  sms_auto_replies: %{
    "opt_in" => "...",
    "opt_out" => "...",
    "help" => "..."
  }
}
```

- Use plain maps (no DB) so the catalog works without fixtures
- Nested assigns like `@event.title` need nested maps with atom keys
- When you add a new `@assign` in an MJML template, add it here too

### Lint (required for precommit)

```bash
mix lint_notification_samples
```

Scans each email `.mjml.eex` (and SMS `preview_keys/0`) and fails if any path is missing from the sample file. Also runs as part of `mix precommit`.

## Editing templates

| Kind | Location |
|------|----------|
| Email modules | `lib/ysc_web/emails/*.ex` |
| Email MJML | `lib/ysc_web/emails/templates/*.mjml.eex` |
| Shared layout | `base_layout`, `header`, `footer` under the same dirs |
| SMS modules | `lib/ysc_web/sms/*.ex` |
| Registration maps | `YscWeb.Emails.Notifier` / `YscWeb.Sms.Notifier` |

Workflow for a new email:

1. Add module + MJML template
2. Register in `Emails.Notifier` `@template_mappings`
3. Add a sample entry under `emails` in `notification_preview_samples.exs`
4. Run `mix lint_notification_samples`
5. Open `/dev/notifications?type=email&name=your_template`

For SMS, also expose `preview_keys/0` (list of assign atoms) so the linter can check the sample map.

## Local render without the browser

```bash
# One or more templates → HTML files
mix ci.email_previews --output-dir /tmp/email_previews \
  --templates membership_ended,welcome_email

# All registered templates (+ newsletter_edition)
mix ci.email_previews --output-dir /tmp/email_previews --all
```

Requires the app to start (Postgres up) because templates call `Endpoint.url/0` via helpers.

## PR screenshots (CI)

On pull requests that change email templates, shared layout, helpers, or the sample file, CI:

1. Detects which templates changed (or re-renders all if layout/samples changed)
2. Renders HTML with the sample config
3. Screenshots with Playwright
4. Updates a **single sticky PR comment** (`<!-- ci-email-previews -->`) with the images
5. Uploads PNG/HTML as workflow artifacts

Images are hosted on branch `ci/email-preview/pr-<N>`. Fork PRs may skip the comment/branch push; artifacts still upload.

Scripts: `etc/scripts/ci/pr_email_previews.sh`, `etc/scripts/ci/screenshot_email_previews.mjs`.

## Common mailbox checks

```bash
make dev

# Registration
# → http://localhost:4000/users/register → /dev/mailbox

# Password reset
# → http://localhost:4000/users/reset-password → /dev/mailbox

# Tickets / bookings
# → complete a purchase or booking → /dev/mailbox
```

## Troubleshooting

**`/dev/notifications` or `/dev/mailbox` 404**  
Confirm `config :ysc, dev_routes: true` in `config/dev.exs` and that you restarted after changing it.

**Lint fails after editing MJML**  
Add the missing keys to `priv/dev/notification_preview_samples.exs` for that template name.

**Preview crashes / blank iframe**  
Render locally with `mix ci.email_previews` to see the error. Often a missing nested key in the sample map.

**Mailbox empty**  
Emails only appear after a real send path runs. Prefer the notification catalog if you only need visual review. Mailbox clears on server restart.

**SMS not in mailbox**  
SMS is not stored in Swoosh. Use the SMS tab on `/dev/notifications`. In dev, Flowroute sends are no-ops unless `FLOWROUTE_FORCE_ENABLE=true`.
