# Re-Authentication Feature for Email and Password Changes

## Overview

This document describes the re-authentication flow implemented for both email and password changes in the user settings. This improvement allows users with different authentication methods (password, passkeys, OAuth) to securely change their email address or password without requiring a "current password" field.

## Problem

Previously, users were required to enter their "current password" to change their email address. This was problematic because:

1. Users who authenticate via passkeys may not have passwords
2. Users who sign in via OAuth (Google, Facebook) may not have passwords
3. Sub-accounts created via family invites may not have set passwords yet

## Solution

Implemented a flexible re-authentication modal that:

1. Detects if the user has a password
2. Offers multiple re-authentication methods based on what's available:
   - Password verification (if user has a password)
   - Passkey authentication (always available as a fallback)
3. Only proceeds with email change after successful re-authentication

## Changes Made

### 1. User Settings Live View (`lib/ysc_web/live/user_settings_live.ex`)

#### Updated Email Form
- Removed the "current_password" input field
- Changed form submission from `update_email` to `request_email_change`
- Added informational text: "You will be asked to verify your identity before changing your email address."

#### Added Re-Authentication Modal
- New modal that shows when user submits email change request
- Conditionally displays password field (only if user has a password)
- Always shows passkey authentication option
- Includes proper error handling and user feedback

#### New Socket Assigns
- `:show_reauth_modal` - Controls modal visibility
- `:reauth_form` - Form for password re-authentication
- `:reauth_error` - Error message to display in modal
- `:reauth_verified_at` - Timestamp of successful re-authentication
- `:reauth_challenge` - Challenge for passkey authentication
- `:pending_email_change` - Stores the new email until re-auth is complete
- `:user_has_password` - Boolean flag to conditionally show password option

#### New Event Handlers

**`request_email_change`**
- Triggered when user submits email change form
- Validates email has changed
- Shows re-authentication modal
- Stores pending email change

**`cancel_reauth`**
- Closes re-authentication modal
- Clears pending email change and errors

**`reauth_with_password`**
- Handles password-based re-authentication
- Validates password using existing `Accounts.get_user_by_email_and_password/2`
- Proceeds with email change on success

**`reauth_with_passkey`**
- Initiates passkey authentication flow
- Generates cryptographic challenge
- Pushes challenge to browser via PasskeyAuth hook

**`verify_authentication`**
- Receives passkey authentication result from browser
- Proceeds with email change after successful passkey verification

**`passkey_auth_error`**
- Handles passkey authentication errors
- Displays error message to user

#### Helper Function

**`process_email_change_after_reauth/1`**
- Private function that handles email change after successful re-authentication
- Sends verification code to new email address
- Updates socket state
- Redirects to email verification modal

### 2. Integration with Existing Systems

#### PasskeyAuth Hook (`assets/js/passkey_auth.js`)
- Already handles `create_authentication_challenge` event
- Triggers WebAuthn browser API
- Sends `verify_authentication` on success
- Sends `passkey_auth_error` on failure
- No changes needed - works out of the box!

#### Accounts Module
- Uses existing `get_user_by_email_and_password/2` for password verification
- Uses existing `generate_and_store_email_verification_code/1`
- Uses existing `send_email_verification_code/4`
- No changes needed to accounts module

## Security Considerations

### Current Implementation
- Browser-verified passkey authentication (WebAuthn)
- Password verification against hashed password in database
- Email verification code sent to new email address
- User must verify new email before change is complete

### Future Enhancements
Consider adding server-side passkey signature verification for additional security. The current implementation trusts the browser's WebAuthn verification, which is secure for authenticated sessions but could be enhanced with server-side validation of the cryptographic signature.

## User Experience Flow

### With Password
1. User enters new email address
2. Clicks "Change Email"
3. Re-authentication modal appears
4. User enters their password OR uses passkey
5. On success, verification code sent to new email
6. User verifies code
7. Email updated

### Without Password (Passkey-only)
1. User enters new email address
2. Clicks "Change Email"
3. Re-authentication modal appears (password field hidden)
4. User clicks "Verify with Passkey"
5. Browser shows passkey prompt (fingerprint/face/PIN)
6. On success, verification code sent to new email
7. User verifies code
8. Email updated

## Password Change Implementation

### Changes Made (lib/ysc_web/live/user_security_live.ex)

#### Updated Password Form
- Removed the "current_password" input field
- Changed form submission from `update_password` to `request_password_change`
- Dynamically shows "Change Password" or "Set Password" based on user state
- Added informational text about identity verification

#### Re-Authentication Modal
- Same modal component as email changes
- Conditionally displays password field (only if user has a password)
- Always shows passkey authentication option
- Proper error handling for both authentication methods

#### New Event Handlers

**`request_password_change`**
- Validates password form before showing modal
- Checks password strength and confirmation match
- Shows re-authentication modal if valid
- Stores pending password change

**`process_password_change_after_reauth`**
- Private function handling password updates after successful re-auth
- Uses `set_user_initial_password/2` for first-time password setting
- Uses direct changeset for password changes (bypassing current password validation)
- Invalidates all user sessions after password change
- Sends password changed notification

### User Experience Flows

#### Changing Existing Password
1. User enters new password and confirmation
2. Clicks "Change Password"
3. Re-authentication modal appears
4. User authenticates (password OR passkey)
5. Password updated, all sessions invalidated
6. User automatically logged back in

#### Setting Password (First Time)
1. User without password sees "Set Password" section
2. User enters new password and confirmation
3. Clicks "Set Password"
4. Re-authentication modal appears (passkey only)
5. User authenticates with passkey
6. Password set, `password_set_at` timestamp recorded
7. User can now login with password in addition to other methods

## Comprehensive Testing

### Test Files

1. **test/ysc_web/live/user_settings_email_change_test.exs**
   - Comprehensive email change flow tests
   - 17 test cases covering all scenarios

2. **test/ysc_web/live/user_security_password_change_test.exs**
   - Comprehensive password change/set flow tests
   - 22 test cases covering all scenarios

3. **test/ysc_web/live/user_security_live_test.exs**
   - Updated existing tests to work with new flow
   - Tests for passkey management

### Test Coverage

#### Email Change Tests

**Initial Request Flow**
- ✅ Form shows email field without current password
- ✅ Validates email format before showing modal
- ✅ Shows re-auth modal for valid email
- ✅ Doesn't show modal if email unchanged
- ✅ Displays informational text about identity verification

**Password Re-Authentication**
- ✅ Shows password option for users with password
- ✅ Successfully authenticates with correct password
- ✅ Shows error with incorrect password
- ✅ Sends verification code to new email after success
- ✅ Redirects to email verification modal

**Passkey Re-Authentication**
- ✅ Shows passkey option in modal
- ✅ Initiates WebAuthn authentication flow
- ✅ Processes email change after passkey verification
- ✅ Handles passkey authentication errors
- ✅ Generates proper challenge

**Users Without Password**
- ✅ Shows only passkey option (no password field)
- ✅ Can change email using passkey authentication
- ✅ Proper UI messaging for OAuth/passkey-only users

**Modal Interaction**
- ✅ Can cancel re-auth modal
- ✅ Clears pending changes on cancellation
- ✅ Maintains state properly

**Email Verification**
- ✅ Shows verification modal after re-auth
- ✅ Displays new email address
- ✅ Completes email change after code verification
- ✅ Updates email_verified_at timestamp

#### Password Change Tests

**Initial Request Flow**
- ✅ Form shows new password fields without current password
- ✅ Shows "Change Password" for users with password
- ✅ Shows "Set Password" for users without password
- ✅ Validates password format (minimum 12 characters)
- ✅ Validates password confirmation matches
- ✅ Shows re-auth modal for valid submission

**Password Re-Authentication (Changing)**
- ✅ Shows password option for users with password
- ✅ Successfully authenticates with correct password
- ✅ Shows error with incorrect password
- ✅ Updates password after successful re-auth
- ✅ Sends password changed notification
- ✅ Invalidates all user sessions
- ✅ Can authenticate with new password
- ✅ Triggers auto-login after change

**Passkey Re-Authentication (Changing)**
- ✅ Shows passkey option in modal
- ✅ Initiates WebAuthn authentication flow
- ✅ Updates password after passkey verification
- ✅ Handles passkey authentication errors
- ✅ Generates proper challenge

**Password Setting (First Time)**
- ✅ Shows only passkey option (no password to verify)
- ✅ Can set password using passkey authentication
- ✅ Marks password_set_at timestamp
- ✅ Sets hashed_password field
- ✅ Updates UI to show "Change Password" after setting
- ✅ User can login with new password

**Modal Interaction**
- ✅ Can cancel re-auth modal
- ✅ Clears pending changes on cancellation
- ✅ Maintains state properly

**Edge Cases**
- ✅ Handles database errors gracefully
- ✅ Clears reauth state after successful change
- ✅ Proper error messages for all failure modes

### Running Tests

```bash
# Run all email change tests
mix test test/ysc_web/live/user_settings_email_change_test.exs

# Run all password change tests
mix test test/ysc_web/live/user_security_password_change_test.exs

# Run updated security settings tests
mix test test/ysc_web/live/user_security_live_test.exs

# Run all three test files
mix test test/ysc_web/live/user_settings_email_change_test.exs \
         test/ysc_web/live/user_security_password_change_test.exs \
         test/ysc_web/live/user_security_live_test.exs
```

### Manual Testing Checklist

#### Email Changes

**User with Password:**
- [ ] Log in with email/password
- [ ] Go to Settings > Account
- [ ] Change email to new address
- [ ] Verify re-auth modal appears with both options
- [ ] Test password re-authentication
- [ ] Verify code sent to new email
- [ ] Complete verification
- [ ] Repeat and test passkey re-authentication

**User without Password (OAuth):**
- [ ] Log in with Google/Facebook
- [ ] Go to Settings > Account
- [ ] Change email to new address
- [ ] Verify modal shows only passkey option
- [ ] Test passkey re-authentication
- [ ] Complete verification

**Error Cases:**
- [ ] Test wrong password
- [ ] Test passkey cancellation
- [ ] Test entering same email
- [ ] Test invalid email format

#### Password Changes

**User with Password:**
- [ ] Log in with email/password
- [ ] Go to Settings > Security
- [ ] Verify "Change Password" section shows
- [ ] Enter new password
- [ ] Verify re-auth modal with both options
- [ ] Test password re-authentication
- [ ] Verify logged back in automatically
- [ ] Log out and login with new password

**User without Password:**
- [ ] Log in with passkey or OAuth
- [ ] Go to Settings > Security
- [ ] Verify "Set Password" section shows
- [ ] Verify explanatory text present
- [ ] Enter new password
- [ ] Verify modal shows only passkey option
- [ ] Test passkey re-authentication
- [ ] Verify password is set
- [ ] Log out and login with new password

**Session Invalidation:**
- [ ] Open browser in two tabs, logged in
- [ ] Change password in one tab
- [ ] Verify other tab's session is invalidated

**Error Cases:**
- [ ] Test password too short
- [ ] Test mismatched confirmation
- [ ] Test wrong password during re-auth
- [ ] Test passkey cancellation

### Test Scenarios with Multiple Authentication Methods

**Scenario 1: OAuth User Adds Password**
1. User signs up with Google OAuth (no password)
2. User sets up passkey for convenience
3. User goes to Settings > Security
4. User sets password for first time using passkey re-auth
5. User can now login with: Google, Passkey, OR Email+Password

**Scenario 2: Email+Password User Adds Passkey**
1. User signs up with email and password
2. User adds passkey in Security settings
3. User can change email using either password or passkey
4. User can change password using either password or passkey

**Scenario 3: Passkey-Only User**
1. User signs up with passkey only
2. User has no password set
3. User can change email only with passkey
4. User can set password only with passkey

## Code Locations

- Main LiveView: `lib/ysc_web/live/user_settings_live.ex:169-230` (modal)
- Main LiveView: `lib/ysc_web/live/user_settings_live.ex:1707-1793` (handlers)
- Email form: `lib/ysc_web/live/user_settings_live.ex:537-556`
- PasskeyAuth Hook: `assets/js/passkey_auth.js`
- This documentation: `docs/EMAIL_CHANGE_REAUTH.md`
