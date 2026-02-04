# Phoenix LiveView Performance Optimization Plan

This document outlines optimizations based on Phoenix LiveView best practices for 2026.

## 1. Efficient Data Management

### ✅ Already Implemented
- **Streams**: Many LiveViews already use streams (admin_users_live, admin_media_live, post_live, events_live, user_tickets_live)
- **Temporary assigns**: Some LiveViews use temporary_assigns for forms (admin_media_live, post_live, admin_posts_live)

### 🔧 Opportunities

#### 1.1 Convert Payments List to Streams
**File**: `lib/ysc_web/live/user_settings_live.ex`
**Issue**: Payments list uses pagination but not streams. Each page load keeps all payments in memory.
**Impact**: Medium - Reduces memory for users with many payments
**Solution**: Convert `@payments` assign to use `stream(:payments, ...)` with pagination

#### 1.2 Add Temporary Assigns for Forms
**Files**: Multiple LiveViews
**Issue**: Forms are kept in memory after render
**Impact**: Low-Medium - Reduces memory footprint
**Solution**: Add `temporary_assigns: [form: nil]` or similar for form assigns

#### 1.3 Use Select for Database Queries
**Files**: Various LiveViews
**Issue**: Loading full schemas when only specific fields are needed
**Impact**: Medium - Reduces data transfer and memory
**Solution**: Use `select` in Ecto queries to fetch only required fields

## 2. Optimizing the Rendering Engine

### ✅ Already Implemented
- **Debouncing**: Widely used across forms (admin_bookings_live, event_details_live, booking_checkout_live)

### 🔧 Opportunities

#### 2.1 Extract LiveComponents from Large LiveViews
**File**: `lib/ysc_web/live/user_settings_live.ex` (4039 lines)
**Issue**: Large monolithic LiveView with many concerns
**Impact**: High - Improves change tracking and reduces diff size
**Solution**: Extract sections into LiveComponents:
  - `UserSettings.ProfileComponent`
  - `UserSettings.MembershipComponent`
  - `UserSettings.PaymentsComponent`
  - `UserSettings.NotificationsComponent`

#### 2.2 Extract Static Parts
**Files**: Multiple LiveViews
**Issue**: Static UI elements are re-rendered on every update
**Impact**: Low-Medium - Reduces diff size
**Solution**: Move static parts (headers, navbars) to functional components

## 3. Handling User Input & External Tasks

### ✅ Already Implemented
- **Background jobs**: Keila subscription sync uses Oban workers
- **Debouncing**: Most form inputs use phx-debounce

### 🔧 Opportunities

#### 3.1 Make Stripe API Calls Async
**File**: `lib/ysc_web/live/user_settings_live.ex`
**Issues**:
- `Stripe.PaymentMethod.retrieve` in `handle_event("payment-method-set")` (line 2294)
- `Stripe.Customer.update` in `handle_event("select-payment-method")` (line 2415)
- `Customers.create_setup_intent` in `handle_event("add-new-payment-method")` (line 2523)
- `Customers.create_subscription` in `handle_event("select_membership")` (line 2157)
- `verify_stripe_customer_exists` in `ensure_stripe_customer_exists` (line 3294)

**Impact**: High - Prevents blocking the LiveView process during API calls
**Solution**: Use `Task.async` for Stripe API calls and `handle_info` to update UI

#### 3.2 Add Debouncing to Missing Inputs
**Files**: Various LiveViews
**Issue**: Some form inputs don't have debouncing
**Impact**: Low - Prevents excessive server requests
**Solution**: Add `phx-debounce="300"` to form inputs

## 4. Monitoring and Tooling

### Recommendations
- Use Phoenix LiveDashboard to monitor process counts and memory usage
- Set up Telemetry hooks to track render times
- Use `:observer` to inspect BEAM processes

## Implementation Priority

### High Priority
1. ✅ Convert payments list to streams (user_settings_live.ex)
2. ✅ Make Stripe API calls async (user_settings_live.ex)
3. ✅ Extract LiveComponents from user_settings_live.ex

### Medium Priority
4. Add temporary_assigns for forms across LiveViews
5. Use select in database queries where appropriate
6. Extract static UI parts to functional components

### Low Priority
7. Add debouncing to remaining form inputs
8. Set up monitoring and telemetry

## Summary Checklist

- [ ] Are you using Streams for dynamic lists? (Partially - payments list needs conversion)
- [ ] Are heavy tasks offloaded to background processes or Task? (Partially - Stripe calls need async)
- [ ] Are you debouncing high-frequency user inputs? (Yes - widely implemented)
- [ ] Are you using temporary_assigns for ephemeral data? (Partially - needs expansion)
