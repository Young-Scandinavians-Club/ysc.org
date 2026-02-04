# Test Coverage Improvement Plan

Generated: 2026-02-02

## Current Status

**Overall Progress:**
- Total Tests: 3,720
- All tests passing (0 failures, 14 skipped)

**Recent Improvements:**
- ✅ Week 1: Added 347 tests, fixed 4 production bugs
- ✅ PaymentSuccessLive: 0% → 64.2% coverage (9 tests)

## Modules with 0% Coverage Analysis

### Priority 1: HIGH - User-Facing Features (Critical Business Logic)

#### 1. Family Invite Acceptance LiveView
**File:** `lib/ysc_web/live/family_invite_acceptance_live.ex` (176 lines)
**Complexity:** Medium
**Business Impact:** High - User onboarding flow
**Effort:** 2-4 hours

**Test Scenarios:**
- Valid invite token acceptance flow
- Invalid/expired token handling
- Already used invite detection
- Form validation (email, password, user details)
- Pre-filling data from primary user
- Family account creation
- Security: prevent unauthorized access

**Dependencies:**
- Ysc.Accounts.FamilyInvites
- Ysc.Accounts.User
- Phoenix.LiveView testing

**Estimated Tests:** 8-12 tests
**Expected Coverage:** 70-80%

---

#### 2. Trix Uploads Controller
**File:** `lib/ysc_web/controllers/trix_uploads_controller.ex` (110 lines)
**Complexity:** Medium
**Business Impact:** High - Content creation with images
**Effort:** 3-5 hours

**Test Scenarios:**
- Successful file upload to S3
- Image validation (MIME types, file extensions)
- Cover photo assignment to posts
- Invalid file type rejection
- File size limits
- S3 upload failure handling
- Image processor integration

**Dependencies:**
- Media.upload_file_to_s3 (needs mocking)
- FileValidator
- Posts context
- S3 configuration

**Estimated Tests:** 10-15 tests
**Expected Coverage:** 65-75%

**Note:** Requires Bypass or similar HTTP mock for S3 interactions

---

### Priority 2: MEDIUM - Background Jobs & Workers

#### 3. Reconciliation Worker
**File:** `lib/ysc/ledgers/reconciliation_worker.ex` (264 lines)
**Complexity:** Medium
**Business Impact:** High - Financial accuracy
**Effort:** 2-3 hours

**Test Scenarios:**
- Successful reconciliation execution
- Discrepancy detection and alerting
- Discord notification on failures
- Oban job worker behavior
- Manual triggering via run_now()
- Error handling and retries

**Dependencies:**
- Reconciliation.run_full_reconciliation (likely already tested)
- Discord alerts
- Oban testing

**Estimated Tests:** 6-10 tests
**Expected Coverage:** 60-70%

**Approach:** Similar to QuickbooksSyncExpenseReportBackupWorker tests

---

#### 4. Property Outage Scheduler
**File:** `lib/ysc/property_outages/scheduler.ex` (44 lines)
**Complexity:** Low
**Business Impact:** Medium
**Effort:** 1 hour

**Test Scenarios:**
- Oban scheduling configuration
- Worker execution
- Error handling

**Estimated Tests:** 3-5 tests
**Expected Coverage:** 70-80%

---

### Priority 3: MEDIUM - UI Components (Partial Testing)

These are large LiveView components with heavy UI rendering. Full coverage is impractical, but core logic can be tested.

#### 5. Admin Events New LiveView
**File:** `lib/ysc_web/live/admin/admin_events_new.ex` (1,092 lines)
**Complexity:** Very High
**Business Impact:** High - Event creation for admins
**Effort:** 8-12 hours (not recommended for immediate coverage push)

**Recommendation:** Focus on mount/handle_event logic only, skip UI rendering tests.

**Testable Logic:**
- Event creation form submission
- Validation handling
- Agenda management
- Date/time formatting
- State transitions (draft → published)

**Expected Coverage:** 20-30% (functional logic only)

---

#### 6. Event Card Component
**File:** `lib/ysc_web/components/events/event_card.ex` (291 lines)
**Complexity:** High
**Business Impact:** Medium
**Effort:** 3-4 hours

**Test Approach:** Test component render with various event states/data

**Expected Coverage:** 40-50%

---

#### 7. News Card Component
**File:** `lib/ysc_web/components/news/news_card.ex` (227 lines)
**Complexity:** Medium
**Business Impact:** Medium
**Effort:** 2-3 hours

**Expected Coverage:** 40-50%

---

#### 8. Autocomplete Component
**File:** `lib/ysc_web/components/autocomplete.ex` (240 lines)
**Complexity:** High (JavaScript interactions)
**Business Impact:** Medium
**Effort:** 4-5 hours

**Expected Coverage:** 30-40%

---

#### 9. Image Upload Component
**File:** `lib/ysc_web/components/image_upload_comp.ex` (191 lines)
**Complexity:** Medium
**Business Impact:** Medium
**Effort:** 3-4 hours

**Expected Coverage:** 40-50%

---

### Priority 4: LOW - Infrastructure & Complex External Dependencies

#### 10. Property Outages Scraper
**File:** `lib/ysc/property_outages/scraper.ex` (1,087 lines)
**Complexity:** Very High
**Business Impact:** Medium
**Effort:** 10-15 hours

**Recommendation:** **SKIP** - Too complex, requires extensive HTTP mocking for multiple utility providers (Kubra.io, Liberty Utilities, PG&E, etc.)

**Alternative:** Integration tests with recorded VCR fixtures if critical

---

#### 11. Authorization Policy
**File:** `lib/ysc_web/authorization/policy.ex` (1,123 lines)
**Complexity:** Medium
**Business Impact:** High
**Effort:** 6-8 hours

**Recommendation:** **DEFER** - Declarative LetMe DSL with extensive policy definitions. Most logic is tested through integration tests of protected endpoints.

**If testing:** Focus on `check/3` calls with different user roles and resources

---

### SKIP: No Testing Needed

These files don't require testing due to their nature:

**Behaviour Definitions (Interface Only):**
- `lib/ysc/customers/behaviour.ex`
- `lib/ysc/keila/behaviour.ex`
- `lib/ysc/payments/behaviour.ex`
- `lib/ysc/quickbooks/client_behaviour.ex`
- `lib/ysc/stripe_behaviour.ex`
- `lib/ysc/stripe/payment_intent_behaviour.ex`
- `lib/ysc/stripe/payment_method_behaviour.ex`
- `lib/ysc/stripe/setup_intent_behaviour.ex`

**Configuration/Infrastructure:**
- `lib/ysc.ex` - Application entry point
- `lib/ysc/mailer.ex` - Mailer config
- `lib/ysc/repo.ex` - Repo config
- `lib/ysc_web/endpoint.ex` - Phoenix endpoint
- `lib/ysc_web/gettext.ex` - I18n
- `lib/ysc_web/telemetry.ex` - Metrics
- `lib/ysc/prom_ex.ex` - Prometheus
- `lib/ysc/release.ex` - Release tasks

**Definition Modules (Constants Only):**
- `lib/ysc/bookings/defs.ex`
- `lib/ysc/events/defs.ex`
- `lib/ysc/property_outages/defs.ex`
- `lib/ysc/encrypted_binary.ex`
- `lib/ysc/membership.ex`
- `lib/ysc/message_passing_events.ex`

**Template Files:**
- `lib/ysc_web/emails/base_layout.ex`

**Trivial Modules:**
- `lib/ysc/stripe_client.ex` (17 lines, wrapper)
- `lib/ysc_web/save_request_uri.ex` (23 lines, simple plug)
- `lib/ysc_web/components/uploader/file_com.ex` (22 lines)

---

## Recommended Implementation Plan

### Week 2 (Current) - Continue High-Value Testing

**Goals:**
- Add 80-120 tests
- Improve 3-4 critical modules from 0% to 60-70%

**Sprint:**

1. **Day 2-3: Family Invite Acceptance (4-6 hours)**
   - Similar pattern to PaymentSuccessLive tests
   - Test mount scenarios, form handling, security
   - **Target:** 8-12 tests, 70-80% coverage

2. **Day 4: Reconciliation Worker (2-3 hours)**
   - Pattern from QuickbooksSyncExpenseReportBackupWorker
   - Test Oban worker behavior, logging, alerting
   - **Target:** 6-10 tests, 60-70% coverage

3. **Day 5: Trix Uploads Controller (3-5 hours)**
   - Requires S3 mocking setup
   - Test file validation, upload flow
   - **Target:** 10-15 tests, 65-75% coverage

**Total Week 2 Expected:** 24-37 new tests

---

### Week 3 - Component Testing (if needed)

Only pursue if Week 1-2 targets are met and stakeholders want more coverage:

1. Event Card Component (3-4 hours)
2. News Card Component (2-3 hours)
3. Image Upload Component (3-4 hours)

**Total Week 3 Expected:** 15-25 new tests

---

### Week 4+ - Advanced/Optional

Only if extremely high coverage is required:

1. Property Outage Scheduler (1 hour)
2. Autocomplete Component (4-5 hours)
3. Selective testing of Admin Events New (mount/core logic only, 4-6 hours)

**DO NOT pursue:**
- Property Outages Scraper (too complex, low ROI)
- Full Authorization Policy testing (covered by integration tests)
- Admin Events New full coverage (UI-heavy, low ROI)

---

## Success Metrics

**Week 2 Targets:**
- Total tests: 3,800+ (from 3,720)
- High-priority modules: 3 improved from 0% to 60-70%
- All tests remain passing
- No new production bugs introduced

**Overall Project Targets:**
- Total tests: 4,000+
- Critical business logic: >70% coverage
- Background workers: >60% coverage
- LiveView/Controllers: >60% coverage

---

## Testing Patterns Established

1. **LiveView Testing:**
   - Use `async: false` when modifying Application config
   - Test mount scenarios (auth, errors, success)
   - Test handle_event callbacks
   - Use dynamic modules for complex mocking
   - Pattern matching on redirect tuples

2. **Oban Worker Testing:**
   - Test perform/1 with mock Oban.Job struct
   - Verify logging and telemetry
   - Test query filtering logic
   - Mock external dependencies
   - Verify worker behavior implementation

3. **Controller Testing:**
   - Use Phoenix.ConnTest
   - Mock external services (S3, APIs)
   - Test happy path and error cases
   - Verify response status codes
   - Test authorization

4. **Component Testing:**
   - Test render with various assigns
   - Focus on conditional logic
   - Test event handling
   - Skip purely visual tests

---

## Notes

- All behaviour files are interfaces with no logic - no tests needed
- Configuration files are declarative - no tests needed
- Large UI-heavy LiveViews should focus on logic, not full rendering
- External API integrations (scraper) require extensive mocking - low ROI
- Prioritize user-facing features and critical business logic
- Maintain test quality over coverage percentage
