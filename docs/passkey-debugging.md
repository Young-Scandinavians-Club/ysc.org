# Passkey Authentication Debugging Guide

## Overview

Comprehensive error logging has been added to the `passkey_auth.js` hook to help diagnose issues, particularly on Firefox mobile.

## What Was Added

### 1. **Sentry Error Tracking**

All error branches now report to Sentry with detailed context:

- **Operation tracking**: Tags identify whether error occurred during registration or authentication
- **Browser detection**: Automatically captures browser type (Firefox, Chrome, Safari, Edge)
- **Error context**: Full error messages, stack traces, and user agent strings
- **Capability detection**: Reports which WebAuthn APIs are available

### 2. **Breadcrumb Tracking**

Key events are logged as breadcrumbs in Sentry:

- When authentication/registration challenges start
- When using legacy vs modern WebAuthn APIs
- When falling back to manual base64 conversion
- When credentials are successfully obtained

### 3. **Enhanced Console Logging**

More detailed console errors with context:

- Configuration errors (missing options, challenge, user data)
- Base64 conversion failures with input details
- Credential creation/retrieval failures

### 4. **LiveView Error Events**

The hook now always pushes error events back to LiveView to prevent the UI from hanging:

- `passkey_auth_error` - Authentication failures
- `passkey_registration_error` - Registration failures
- Both include error name and message for UI display

## Debugging Firefox Mobile Issues

### Common Issues on Firefox Mobile

1. **No Passkey Support**
   - Check console for: `[PasskeyAuth] Error pushing passkey_support_detected event`
   - Sentry will show: `component: passkey_auth, event: passkey_support_detected`

2. **Challenge Parsing Failures**
   - Look for: `Empty challenge from parseRequestOptionsFromJSON`
   - Will automatically fall back to manual conversion

3. **Missing Configuration**
   - Errors like: `Challenge is required but was not provided`
   - Check that server is sending proper options

4. **User Cancellation**
   - Error name: `NotAllowedError`
   - Message: User canceled or dismissed the prompt

### How to Debug

1. **Open Browser Console (Firefox Mobile)**
   ```
   about:debugging → This Firefox → Inspect (next to your page)
   ```

2. **Look for PasskeyAuth Messages**
   - All messages start with `[PasskeyAuth]`
   - Errors include full context objects

3. **Check Sentry Dashboard**
   - Filter by: `component:passkey_auth`
   - Look at breadcrumbs to see execution flow
   - Check extra data for full context

4. **Common Error Names**
   - `NotAllowedError`: User canceled or timeout
   - `NotSupportedError`: Browser doesn't support the feature
   - `SecurityError`: Origin/RP mismatch or HTTPS issue
   - `InvalidStateError`: Credential already registered
   - `UnknownError`: Generic failure (check Sentry for details)

## Testing the Fix

### Basic Test Flow

1. Open Firefox mobile browser
2. Navigate to passkey registration/login page
3. Click the passkey button
4. Open DevTools via USB debugging or about:debugging
5. Check console for detailed error messages
6. Check Sentry for captured exceptions

### Expected Console Output (Success)

```
[PasskeyAuth] Starting authentication challenge
[PasskeyAuth] Authentication credential obtained successfully
```

### Expected Console Output (Error)

```
[PasskeyAuth] Starting authentication challenge
[PasskeyAuth] parseRequestOptionsFromJSON failed, falling back to manual conversion
[PasskeyAuth] Passkey authentication failed NotAllowedError: User canceled
```

## Sentry Error Tags

All passkey errors are tagged with:

```javascript
{
  component: "passkey_auth",
  operation: "authentication" | "registration",
  error_name: "NotAllowedError" | "SecurityError" | etc.,
  browser: "Firefox" | "Chrome" | "Safari" | "Edge"
}
```

## Next Steps

With this enhanced logging:

1. **Try Firefox mobile again** - All errors will now be captured
2. **Check Sentry** - Look for new passkey_auth errors
3. **Review console logs** - See exactly where it's failing
4. **Share error details** - The error context will help identify the issue

## Related Files

- `/assets/js/passkey_auth.js` - Main hook with error logging
- `/docs/sentry-user-context.md` - Sentry user context documentation
- `/assets/js/app.js` - Sentry initialization
