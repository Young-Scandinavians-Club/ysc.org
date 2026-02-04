# User Settings Live Refactoring Plan

## Current State

`lib/ysc_web/live/user_settings_live.ex` is **4,038 lines** and handles:
- Profile management
- Email/phone verification
- Password changes
- Membership management
- Payment method management
- Payment history
- Notification preferences
- Billing address management

## Refactoring Strategy

### Phase 1: Extract Verification Components

Extract phone and email verification modals into separate LiveComponents:

1. **`YscWeb.UserSettingsLive.PhoneVerificationComponent`**
   - Handles phone verification modal
   - Events: `validate_phone_code`, `verify_phone_code`, `resend_phone_code`
   - Reduces ~200 lines

2. **`YscWeb.UserSettingsLive.EmailVerificationComponent`**
   - Handles email verification modal
   - Events: `validate_email_code`, `verify_email_code`, `resend_email_code`
   - Reduces ~200 lines

### Phase 2: Extract Payment Components

3. **`YscWeb.UserSettingsLive.PaymentMethodComponent`**
   - Handles payment method selection and addition
   - Events: `select-payment-method`, `add-new-payment-method`, `cancel-new-payment-method`
   - Reduces ~300 lines

4. **`YscWeb.UserSettingsLive.PaymentHistoryComponent`**
   - Handles payment list display and pagination
   - Events: `next-payments-page`, `prev-payments-page`, `filter-payments`
   - Reduces ~400 lines

### Phase 3: Extract Form Sections

5. **`YscWeb.UserSettingsLive.ProfileSectionComponent`**
   - Profile form and profile picture section
   - Events: `validate_profile`, `update_profile`
   - Reduces ~150 lines

6. **`YscWeb.UserSettingsLive.MembershipSectionComponent`**
   - Membership management section
   - Events: `select_membership`, `change-membership`, `cancel-membership`, `reactivate-membership`
   - Reduces ~600 lines

7. **`YscWeb.UserSettingsLive.NotificationsSectionComponent`**
   - Notification preferences form
   - Events: `validate_notifications`, `update_notifications`
   - Reduces ~100 lines

8. **`YscWeb.UserSettingsLive.AddressSectionComponent`**
   - Billing address form
   - Events: `validate_address`, `update_address`
   - Reduces ~100 lines

### Phase 4: Extract Business Logic

Move complex business logic to context modules:

9. **`Ysc.Accounts.UserSettings`** - New context module
   - `ensure_stripe_customer_exists/1`
   - `get_membership_type_for_selection/1`
   - `sync_mailpoet_subscription/2`
   - Payment method helpers

10. **`Ysc.Payments.PaymentDisplay`** - New helper module
    - `payment_method_display_text/1`
    - `payment_method_icon/1`
    - `render_payment_card/1`
    - `render_payment_table_row/1`
    - Payment filtering and statistics

### Phase 5: Extract Sidebar

11. **`YscWeb.UserSettingsLive.SidebarComponent`**
    - Navigation sidebar
    - Reduces ~100 lines

## Implementation Steps

1. Create component modules one at a time
2. Move event handlers to components
3. Update render function to use components
4. Move business logic to context modules
5. Test each extraction incrementally
6. Remove old code after verification

## Expected Results

- Main LiveView: ~1,500-2,000 lines (manageable)
- Components: 8-10 focused components (~100-400 lines each)
- Context modules: Business logic separated
- Better testability
- Easier maintenance
- Improved performance (smaller LiveView processes)

## Notes

- Keep parent-child communication via `send_update` or assigns
- Use `live_component` for stateful components
- Use regular components for stateless UI sections
- Maintain backward compatibility during refactoring
