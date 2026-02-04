# Re-Authentication Testing Guide

## Quick Start

This guide provides step-by-step instructions for manually testing the email and password change re-authentication flows.

## Prerequisites

1. Have at least 3 test users ready:
   - User with password only
   - User with passkey (and optionally password)
   - User from OAuth (Google/Facebook) without password

2. Ensure you have access to:
   - Email inbox (for email verification codes)
   - Browser with WebAuthn support (Chrome, Safari, Firefox, Edge)

## Test Scenarios

### Scenario 1: Email Change with Password Re-Auth

**User:** Regular user with password

**Steps:**
1. Log in with email and password
2. Navigate to Settings > Account
3. Find "Email" section
4. Verify current password field is NOT present
5. Enter new email address (e.g., newemail@example.com)
6. Click "Change Email"
7. **Verify:** Re-authentication modal appears
8. **Verify:** Modal shows "Verify Your Identity"
9. **Verify:** Modal shows both "Sign in with password" and "Verify with Passkey" options
10. Enter your current password in modal
11. Click "Verify with Password"
12. **Verify:** Modal closes
13. **Verify:** Email verification modal appears
14. **Verify:** Message says code sent to new email
15. Check email inbox for verification code
16. Enter 6-digit code
17. Click "Verify Email Address"
18. **Verify:** Email updated successfully
19. **Verify:** email_verified_at timestamp set

**Expected Results:**
- ✅ No current password field in main form
- ✅ Re-auth modal shows both options
- ✅ Password authentication works
- ✅ Email verification flow completes
- ✅ Email successfully changed

---

### Scenario 2: Email Change with Passkey Re-Auth

**User:** User with password (testing alternate auth method)

**Steps:**
1. Log in with email and password
2. Navigate to Settings > Account
3. Enter new email address
4. Click "Change Email"
5. **Verify:** Re-authentication modal appears
6. Click "Verify with Passkey" (do NOT use password)
7. **Verify:** Browser prompts for biometric/PIN
8. Complete biometric authentication
9. **Verify:** Modal closes
10. **Verify:** Email verification modal appears
11. Complete email verification with code

**Expected Results:**
- ✅ Passkey authentication works as alternative
- ✅ Browser WebAuthn prompt appears
- ✅ Email change proceeds after passkey verification

---

### Scenario 3: Email Change for OAuth User

**User:** User logged in via Google/Facebook (no password)

**Steps:**
1. Log in with Google or Facebook
2. Navigate to Settings > Account
3. **Verify:** Email form shows without password field
4. Enter new email address
5. Click "Change Email"
6. **Verify:** Re-authentication modal appears
7. **Verify:** Modal does NOT show password option
8. **Verify:** Modal shows "Sign in with your passkey" (no "OR" divider)
9. Click "Verify with Passkey"
10. Complete biometric authentication
11. Complete email verification

**Expected Results:**
- ✅ No password field in form
- ✅ Re-auth modal shows only passkey option
- ✅ No confusing password authentication option
- ✅ Email change completes successfully

---

### Scenario 4: Password Change with Password Re-Auth

**User:** Regular user with password

**Steps:**
1. Log in with email and password
2. Navigate to Settings > Security
3. Find "Change Password" section
4. **Verify:** Current password field is NOT present
5. **Verify:** Section title says "Change Password" (not "Set Password")
6. Enter new password (12+ characters)
7. Enter password confirmation
8. Click "Change Password"
9. **Verify:** Re-authentication modal appears
10. **Verify:** Modal shows both authentication options
11. Enter current password in modal
12. Click "Verify with Password"
13. **Verify:** Modal closes
14. **Verify:** Automatically logged back in
15. Log out
16. Log in with NEW password
17. **Verify:** Login successful

**Expected Results:**
- ✅ No current password in main form
- ✅ Title shows "Change Password"
- ✅ Password authentication works
- ✅ All sessions invalidated
- ✅ Auto-logged back in
- ✅ New password works

---

### Scenario 5: Password Change with Passkey Re-Auth

**User:** User with password

**Steps:**
1. Log in with email and password
2. Navigate to Settings > Security
3. Enter new password and confirmation
4. Click "Change Password"
5. In re-auth modal, click "Verify with Passkey" (NOT password)
6. Complete biometric authentication
7. **Verify:** Password changed successfully
8. Log out
9. Log in with new password

**Expected Results:**
- ✅ Passkey works for password change re-auth
- ✅ New password works after change

---

### Scenario 6: Setting Password for First Time

**User:** OAuth user or passkey-only user without password

**Steps:**
1. Log in (via Google/Facebook or passkey)
2. Navigate to Settings > Security
3. **Verify:** Section title says "Set Password" (not "Change Password")
4. **Verify:** Explanatory text about setting password is shown
5. Enter new password (12+ characters)
6. Enter password confirmation
7. Click "Set Password"
8. **Verify:** Re-authentication modal appears
9. **Verify:** Modal shows ONLY passkey option (no password option)
10. **Verify:** Modal says "setting a password" (not "changing")
11. Click "Verify with Passkey"
12. Complete biometric authentication
13. **Verify:** Success message or indication
14. Log out
15. **Verify:** Can now log in with email and new password
16. Log back in with password
17. Navigate to Settings > Security
18. **Verify:** Section now says "Change Password"

**Expected Results:**
- ✅ UI shows "Set Password" for users without password
- ✅ Explanatory text present
- ✅ Re-auth modal shows only passkey
- ✅ Password successfully set
- ✅ password_set_at timestamp recorded
- ✅ Can login with new password
- ✅ UI updates to "Change Password" after setting

---

### Scenario 7: Modal Cancellation

**Steps:**
1. Start email change flow
2. When re-auth modal appears, click X or Cancel
3. **Verify:** Modal closes
4. **Verify:** Email form still shows original email
5. **Verify:** No error messages
6. Repeat for password change flow

**Expected Results:**
- ✅ Can cancel re-auth modal
- ✅ No errors on cancellation
- ✅ Form state preserved

---

### Scenario 8: Error Handling - Wrong Password

**Steps:**
1. Start email change flow
2. In re-auth modal, enter WRONG password
3. Click "Verify with Password"
4. **Verify:** Error message appears: "Invalid password. Please try again."
5. **Verify:** Modal stays open
6. Enter correct password
7. **Verify:** Proceeds successfully

**Expected Results:**
- ✅ Clear error message
- ✅ Modal stays open for retry
- ✅ Can recover from error

---

### Scenario 9: Error Handling - Passkey Cancelled

**Steps:**
1. Start password change flow
2. Click "Verify with Passkey"
3. When browser prompts, click "Cancel" or close prompt
4. **Verify:** Error message appears in modal
5. **Verify:** Modal stays open
6. Retry with passkey
7. Complete authentication

**Expected Results:**
- ✅ Handles passkey cancellation gracefully
- ✅ Can retry after cancellation

---

### Scenario 10: Session Invalidation

**Setup:** Open browser with two tabs, logged in

**Steps:**
1. In Tab 1: Navigate to Settings > Security
2. In Tab 2: Keep on any authenticated page
3. In Tab 1: Change password with re-auth
4. Wait for password change to complete
5. In Tab 2: Try to perform authenticated action
6. **Verify:** Tab 2 session is invalid
7. **Verify:** Redirected to login in Tab 2

**Expected Results:**
- ✅ All sessions invalidated after password change
- ✅ Other tabs logged out
- ✅ Security maintained

---

## Validation Checks

### Email Change Validation
- [ ] No current password field in form
- [ ] Re-auth modal appears before change
- [ ] Both auth methods work (password & passkey)
- [ ] OAuth users see only passkey option
- [ ] Verification code sent to new email
- [ ] Email updated after verification
- [ ] email_verified_at timestamp set

### Password Change Validation
- [ ] No current password field in form
- [ ] Shows "Change Password" for users with password
- [ ] Shows "Set Password" for users without password
- [ ] Re-auth modal appears before change
- [ ] Both auth methods work (password & passkey)
- [ ] Users without password see only passkey option
- [ ] All sessions invalidated after change
- [ ] Auto-logged back in after change
- [ ] New password works
- [ ] password_set_at timestamp set (first-time only)
- [ ] Notification email sent

### Error Handling Validation
- [ ] Wrong password shows clear error
- [ ] Passkey cancellation handled gracefully
- [ ] Can retry after errors
- [ ] Modal can be cancelled
- [ ] Form validation works (email format, password length, etc.)
- [ ] Same email/password shows appropriate message

## Browser Compatibility

Test in at least two browsers:
- [ ] Chrome/Chromium
- [ ] Safari (macOS/iOS)
- [ ] Firefox
- [ ] Edge

### WebAuthn/Passkey Testing
- [ ] macOS: Touch ID works
- [ ] Windows: Windows Hello works
- [ ] iOS: Face ID works
- [ ] Android: Fingerprint works
- [ ] Hardware key: Works if available

## Performance Checks

- [ ] Re-auth modal appears instantly
- [ ] No noticeable delay in form submission
- [ ] Email verification code arrives within 1 minute
- [ ] Password change completes in < 5 seconds
- [ ] Auto-login after password change is instant

## Security Checks

- [ ] Cannot change email without re-authentication
- [ ] Cannot change password without re-authentication
- [ ] Sessions invalidated after password change
- [ ] Email verification required for email change
- [ ] No passwords stored in browser localStorage
- [ ] WebAuthn challenge is unique each time
- [ ] Cannot replay passkey authentication

## Accessibility Testing

- [ ] Can navigate forms with keyboard only
- [ ] Tab order is logical
- [ ] Enter key submits forms
- [ ] Escape key closes modal
- [ ] Screen reader announces modal opening
- [ ] Error messages are announced
- [ ] Form labels are clear

## Regression Testing

Test these still work after changes:
- [ ] Regular login with password
- [ ] Login with passkey
- [ ] OAuth login (Google/Facebook)
- [ ] Other settings pages load correctly
- [ ] Password reset flow still works
- [ ] Phone number verification still works
- [ ] Profile updates still work

## Automated Test Verification

Run the test suite:

```bash
# All re-auth tests
mix test test/ysc_web/live/user_settings_email_change_test.exs \
         test/ysc_web/live/user_security_password_change_test.exs \
         test/ysc_web/live/user_security_live_test.exs

# Expected output: All tests pass (39 tests total)
```

**Verify test output:**
- [ ] 17 email change tests pass
- [ ] 22 password change tests pass
- [ ] Updated security live tests pass
- [ ] No compilation warnings
- [ ] No test failures

## Issue Reporting Template

If you find issues, report with:

```
**Feature:** Email Change / Password Change / Password Setting
**User Type:** Password user / Passkey user / OAuth user
**Browser:** Chrome 120 / Safari 17 / Firefox 121 / etc.
**Auth Method Tested:** Password / Passkey

**Steps to Reproduce:**
1.
2.
3.

**Expected Result:**


**Actual Result:**


**Screenshots:**
[Attach if relevant]

**Console Errors:**
[Paste JavaScript console errors if any]
```

## Success Criteria

All scenarios pass ✅
- Email changes work with both auth methods
- Password changes work with both auth methods
- Password setting works for first-time users
- OAuth users can use passkey re-auth
- Error handling is graceful
- Sessions invalidate correctly
- All automated tests pass

## Notes

- Test with real email addresses to verify delivery
- Use dev/sandbox mode if available for quick testing
- Clear browser cache if experiencing issues
- Test in incognito/private mode for clean state
- Keep browser DevTools console open to catch errors
