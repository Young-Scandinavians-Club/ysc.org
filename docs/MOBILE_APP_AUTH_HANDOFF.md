# Mobile app sign-in handoff (browser → native app)

The YSC Admin app (`../ysc-admin-mobile`) has no login form of its own. It
opens ysc.org's real login page in a system browser tab
(`WebBrowser.openAuthSessionAsync`), lets the user sign in with whatever
method the website supports, and then the website hands a **one-time code**
back to the app. The app exchanges that code for a bearer token at
`POST /api/v1/app/auth/exchange`.

## Flow

```
app: signIn()
  └─ open Custom Tab → https://<host>/users/log-in
                         ?mobile_redirect_uri=<REDIRECT>
                         &code_challenge=<sha256 hex>

user signs in (password / Google / Facebook / …)

server:
  - fresh login          → UserAuth.log_in_user/6
  - already signed in     → GET /users/log-in redirects to
                            GET /users/log-in/mobile-handoff (a CSRF-guarded
                            confirmation page — Finding 49: never mint on GET)
                            → POST /users/log-in/mobile-handoff
                              → UserAuth.complete_mobile_handoff/1

  both paths end in UserAuth.send_mobile_app_handoff/3, which renders an
  HTML page (NOT a 302) that sends "<REDIRECT>?code=<one-time code>" to the
  app.

app: Linking listener / openAuthSessionAsync result fires with the code
  └─ POST /api/v1/app/auth/exchange { code, code_verifier } → { token, user }
```

`<REDIRECT>` is one of `UserAuth`'s `@allowed_mobile_redirect_uris`
(strict exact-match allowlist):

| Redirect | When the app uses it |
| --- | --- |
| `https://ysc.org/app/auth-callback` | prod builds |
| `https://ysc-sandbox.fly.dev/app/auth-callback` | sandbox / dev builds |
| `ysc-admin://auth-callback` | local dev (http backend), and the fallback the App Link landing page bounces to |

## Why an HTML page and not `redirect(conn, external: …)`

Chrome for Android **silently drops** an HTTP 3xx whose `Location` is a
private-use scheme (`ysc-admin://…`) and never fires the intent. It also
only hands *any* navigation — custom scheme or verified `https://` App Link
— to an installed app when the navigation carries a real **user
activation**; a server redirect has none.

So `send_mobile_app_handoff/3` renders a page that:

1. tries `window.location.replace(<REDIRECT>?code=…)` on load (honoured by
   some browsers, and once the App Link is verified);
2. arms the next tap / keypress anywhere as a real gesture that does get
   handed off;
3. shows an "Open the YSC Admin app" button as the reliable path.

The inline `<script>` **must** carry the request's CSP nonce
(`conn.assigns[:csp_nonce]`) — `script-src-elem` has no `'unsafe-inline'`.

## Android App Links setup

App Links let a verified `https://` link open the app directly with no
interstitial, and degrade to a normal web page when the app isn't
installed. Three things must line up:

### 1. `assetlinks.json` on every host (this repo)

Served at `https://<host>/.well-known/assetlinks.json` (static file:
`priv/static/.well-known/assetlinks.json`, served by the endpoint's
`.well-known` `Plug.Static`). Same file is deployed to both `ysc.org` and
`ysc-sandbox.fly.dev` since they run the same app.

`sha256_cert_fingerprints` holds the fingerprint of the EAS-managed
release keystore for `org.ysc.admin`
(`F8:74:4E:2C:…:E6`). EAS uses one keystore per app, so `preview` and
`production` builds share it. It was read from a shipped build's APK
signature:

```bash
cd ../ysc-admin-mobile
eas build:list --platform android --limit 1 --json --non-interactive
#   → download the .apk from applicationArchiveUrl, then:
#   apksigner verify --print-certs app.apk        # SDK build-tools
#   (or) keytool -printcert -jarfile app.apk      # only if v1-signed
```

or interactively via `eas credentials --platform android` → *Keystore* →
"SHA256 Fingerprint".

**Re-check after any keystore change** (a rotated or re-uploaded keystore
changes the fingerprint). If the app is ever shipped through Play Store
**Play App Signing**, add that cert's fingerprint too (Play Console → *Test
and release* → *App integrity* → *App signing key certificate* → SHA-256) —
`sha256_cert_fingerprints` is a list.

### 2. Intent filters in the app (`../ysc-admin-mobile/app.json`)

`android.intentFilters` declares an `autoVerify` filter for
`https://ysc.org/app/auth-callback` and
`https://ysc-sandbox.fly.dev/app/auth-callback`. `expo prebuild`
regenerates `android/` from this — the native `android/` dir is gitignored,
so a build (`eas build` / `make android`) always picks it up.

### 3. Deploy, then verify

```bash
# assetlinks.json reachable, correct content type, no redirect:
curl -sI https://ysc.org/.well-known/assetlinks.json
curl -sI https://ysc-sandbox.fly.dev/.well-known/assetlinks.json
#   → 200, content-type: application/json

# Google's tester:
#   https://developers.google.com/digital-asset-links/tools/generator

# On a device with the app installed, after a build with the intent filters:
adb shell pm get-app-links org.ysc.admin
#   → each domain should show "verified"
# Force re-verification if needed:
adb shell pm verify-app-links --re-verify org.ysc.admin
```

Until verification succeeds the flow still works via the fallback: the App
Link URL loads `GET /app/auth-callback` (see
`UserSessionController.app_auth_callback/2`), which bounces the code to
`ysc-admin://auth-callback` and shows the button.
