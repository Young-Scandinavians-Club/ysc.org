# Authentication: Step-Up Re-Auth and Passkeys

Members can sign in with a password, a passkey (WebAuthn) or OAuth (Google / Facebook). Many accounts have no password (passkey-only, OAuth-only, or family sub-accounts), so sensitive changes cannot depend on "current password".

## Step-up re-authentication

Sensitive settings changes — **email, phone, password** — require a recent re-authentication, not a password field.

**How it works**

1. The user submits the form (e.g. `request_email_change`, `request_password_change`). If the session already has a valid re-auth, the change proceeds immediately; otherwise a re-auth modal opens.
2. The modal offers whatever the account supports: password (only if the user has one), passkey (WebAuthn), or OAuth.
3. On success the session records `reauth_verified_at`. `YscWeb.UserAuth` (`:mount_reauth_session` on_mount hook) turns that into `session_reauth_verified` / `session_reauth_expires_at` assigns. **The window is 300 seconds** (`@reauth_ttl_seconds`), and handlers re-check the absolute expiry at action time rather than trusting a flag frozen at mount.
4. The pending change then continues (e.g. a verification code is sent to the new email address; the change only completes once that code is verified).

**OAuth leaves the LiveView**, so the pending intent travels in the `return_to` URL as an encrypted token (`YscWeb.ReauthResume`, 10-minute max age). The token is bound to the `user_id` that started the flow; it is rejected if a different user opens it.

**Security rules to preserve**

- An admin impersonating a member never inherits the admin's own re-auth as step-up for the member (`reauth_still_valid?` returns false while `impersonating?`).
- Login and step-up re-auth go through the same passkey verification path in `Ysc.Accounts` (including the signature-counter / cloned-authenticator check), so a credential rejected at login cannot pass re-auth.
- Never reintroduce a "current password" requirement for these flows.

**Where**: `lib/ysc_web/user_auth.ex`, `lib/ysc_web/reauth_resume.ex`, `lib/ysc_web/live/user_security_live.ex`, `lib/ysc_web/live/user_settings_live.ex`, the re-auth modal in `core_components.ex`, `assets/js/passkey_auth.js`. Tests: `test/ysc_web/reauth_resume_test.exs` plus the LiveView tests for the settings pages.

### Manual test matrix

Use three users: password-only, passkey (± password), and OAuth-only. For each of email change and password change:

| User         | Expect in the re-auth modal                  | Then                                                   |
| ------------ | -------------------------------------------- | ------------------------------------------------------ |
| Password     | Password field and passkey option            | Wrong password shows an error; correct one proceeds    |
| Passkey-only | No password field; passkey button            | Browser passkey prompt, then the flow proceeds         |
| OAuth-only   | OAuth option                                 | Round trip to the provider, resume with the pending change intact |

Also check: cancelling closes the modal and drops the pending change; a second change within 5 minutes skips the modal; after 5 minutes it asks again.

## Passkey debugging

The `PasskeyAuth` hook (`assets/js/passkey_auth.js`) reports every failure to Sentry and always pushes an error event back to the LiveView (`passkey_auth_error`, `passkey_registration_error`) so the UI never hangs.

**Sentry tags**: `component: passkey_auth`, `operation: authentication | registration`, `error_name`, `browser`. Breadcrumbs record the challenge start, legacy-vs-modern WebAuthn API choice and the base64 fallback. Filter Sentry by `component:passkey_auth` and read the breadcrumbs for the execution path.

**Console**: every message is prefixed `[PasskeyAuth]`. On Firefox mobile use `about:debugging` → This Firefox → Inspect.

| `error_name`         | Usual meaning                                           |
| -------------------- | ------------------------------------------------------- |
| `NotAllowedError`    | User cancelled the prompt, or it timed out              |
| `NotSupportedError`  | Browser/device doesn't support the feature              |
| `SecurityError`      | Origin / relying-party id mismatch, or not HTTPS        |
| `InvalidStateError`  | Credential already registered on this authenticator     |
| `UnknownError`       | Check the Sentry event's extra data                     |

`Empty challenge from parseRequestOptionsFromJSON` means the hook fell back to manual base64 conversion (expected on older browsers); `Challenge is required but was not provided` means the server sent incomplete options.
