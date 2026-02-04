# Migration Epic: WordPress to Phoenix/Elixir

## Overview

This document outlines the complete migration strategy from the existing WordPress/WooCommerce/UltimateMember stack to the new Phoenix/Elixir application. The migration must ensure zero data loss, maintain Stripe customer continuity, and preserve all membership information.

## Migration Timeline Strategy

1. **Pre-Migration Phase**: Preparation and tooling (2-3 weeks)
2. **Sandbox Testing Phase**: Full migration dry-run in sandbox (1 week)
3. **Production Migration Execution**: Maintenance window (4-8 hours estimated)
4. **Post-Migration Phase**: Validation and monitoring (1 week)

---

## Epic Tasks

### Phase 1: Pre-Migration Preparation

#### Task 1.1: WordPress Data Assessment & Export Strategy
**Priority**: Critical | **Estimated Effort**: 3-5 days

**Objectives**:
- Audit all WordPress database tables for UltimateMember, WooCommerce, and core WP data
- Document exact field mappings from WordPress to Phoenix schema
- Identify data inconsistencies or edge cases

**Deliverables**:
- [ ] Complete WordPress database schema documentation
- [ ] Field mapping spreadsheet (WordPress → Phoenix)
- [ ] List of custom fields and meta data that need migration
- [ ] Data quality report (missing emails, duplicate users, invalid states, etc.)
- [ ] Count of total records per entity type:
  - Users (wp_users, wp_usermeta, ultimatemember tables)
  - Membership applications (ultimatemember form submissions)
  - Products and orders (woocommerce tables)
  - Stripe customer associations
  - Active subscriptions
  - Posts (wp_posts where post_type = 'post')
  - Media attachments (wp_posts where post_type = 'attachment')

**SQL Queries Needed**:
```sql
-- Count active users
SELECT COUNT(*) FROM wp_users WHERE user_status = 0;

-- Count published posts
SELECT COUNT(*) FROM wp_posts WHERE post_status = 'publish' AND post_type = 'post';

-- Count media attachments
SELECT COUNT(*) FROM wp_posts WHERE post_type = 'attachment';

-- Count WooCommerce orders
SELECT COUNT(*) FROM wp_posts WHERE post_type = 'shop_order';

-- List custom user meta keys
SELECT DISTINCT meta_key FROM wp_usermeta ORDER BY meta_key;
```

**Acceptance Criteria**:
- All WordPress tables are documented
- Field mappings validated by comparing sample records
- Edge cases identified and migration strategy defined

---

#### Task 1.2: Stripe Subscription Audit
**Priority**: Critical | **Estimated Effort**: 2-3 days

**Objectives**:
- Verify all WordPress users with active subscriptions have Stripe customer IDs
- Ensure Stripe customer data is consistent with WordPress data
- Document subscription product/price IDs used in production

**Deliverables**:
- [ ] Export all Stripe customers with subscriptions
- [ ] Cross-reference Stripe customer IDs with WordPress user accounts
- [ ] List of orphaned Stripe customers (no WordPress user)
- [ ] List of orphaned WordPress subscriptions (no Stripe customer)
- [ ] Document active Stripe price IDs and their meanings
- [ ] Verify subscription metadata fields used

**API Tasks**:
```bash
# Export all customers with subscriptions
stripe customers list --limit 100 > stripe_customers.json

# Export all active subscriptions
stripe subscriptions list --status=active --limit 100 > stripe_subscriptions.json

# Export all subscription products
stripe products list --limit 100 > stripe_products.json

# Export all prices
stripe prices list --limit 100 > stripe_prices.json
```

**Acceptance Criteria**:
- 100% of active subscriptions in WordPress matched to Stripe
- All discrepancies documented with resolution plan
- Stripe product/price mapping to membership tiers complete

---

#### Task 1.3: Build Migration Tooling (Mix Tasks)
**Priority**: Critical | **Estimated Effort**: 5-7 days

**Objectives**:
- Create Mix tasks for each migration step
- Build validation and rollback capabilities
- Implement dry-run mode for testing

**Deliverables**:
- [ ] `mix migrate.users` - User account migration
- [ ] `mix migrate.subscriptions` - Subscription migration
- [ ] `mix migrate.posts` - Blog post migration
- [ ] `mix migrate.media` - Media library migration
- [ ] `mix migrate.validate` - Post-migration validation
- [ ] `mix migrate.dry_run` - Test run without database writes

**Technical Requirements**:
- All tasks must be idempotent (can run multiple times safely)
- Progress tracking with ETS or database table
- Detailed logging to file
- Error handling with continue-on-error option
- Batch processing for large datasets
- Transaction support with rollback capability

**Example Task Structure**:
```elixir
defmodule Mix.Tasks.Migrate.Users do
  use Mix.Task
  alias Ysc.Repo
  
  @shortdoc "Migrate users from WordPress MySQL dump"
  
  def run(args) do
    Mix.Task.run("app.start")
    
    opts = parse_args(args)
    
    # Connect to WordPress DB or load SQL dump
    # Process in batches
    # Log progress
    # Handle errors
    
    if opts.dry_run do
      IO.puts("DRY RUN: Would migrate X users")
    else
      # Actual migration
    end
  end
end
```

**Acceptance Criteria**:
- All Mix tasks created and tested with sample data
- Dry-run mode produces accurate reports
- Error handling prevents partial migrations
- Progress can be resumed if interrupted

---

#### Task 1.4: Sandbox Environment Preparation
**Priority**: High | **Estimated Effort**: 2-3 days

**Objectives**:
- Prepare sandbox environment for migration testing
- Load WordPress backup into sandbox for testing
- Configure for complete migration dry-run

**Deliverables**:
- [ ] Sandbox Fly.io environment verified (fly-sandbox.toml exists)
- [ ] Sandbox database cleared and ready
- [ ] WordPress database dump loaded into accessible location
- [ ] S3 sandbox bucket for media uploads
- [ ] Test Stripe account configured (use test mode keys)
- [ ] Sandbox-specific environment variables configured

**Sandbox vs Production**:
```bash
# Deploy to sandbox
fly deploy --config etc/fly/fly-sandbox.toml

# Use sandbox-specific env vars
# STRIPE_SECRET_KEY=sk_test_...
# AWS_S3_BUCKET=ysc-sandbox-media
# DATABASE_URL=sandbox-postgres-url
```

**Acceptance Criteria**:
- Sandbox environment fully functional
- Can access WordPress data from sandbox Phoenix app
- S3 uploads working in sandbox
- Stripe test mode webhooks configured
- Sandbox isolated from production data

---

#### Task 1.5: Media Migration Strategy & S3 Upload Plan
**Priority**: High | **Estimated Effort**: 3-4 days

**Objectives**:
- Plan efficient media file transfer to S3
- Handle large media library without timeout
- Preserve image metadata and associations

**Deliverables**:
- [ ] S3 bucket structure design
- [ ] Media migration script with progress tracking
- [ ] Image processing pipeline (thumbnails, optimization)
- [ ] CDN/CloudFront configuration (if applicable)
- [ ] Backup plan for WordPress media files

**Technical Considerations**:
- WordPress stores media in `wp-content/uploads/YYYY/MM/filename.ext`
- Phoenix expects images in S3 with paths in database
- Must handle:
  - Original images
  - WordPress-generated thumbnails (may regenerate instead)
  - Image metadata (alt text, captions)
  - Post featured images associations

**Migration Process**:
1. Download all WordPress media to temporary storage
2. Upload to S3 in batches
3. Create `images` table records
4. Process images asynchronously with Oban
5. Associate with posts

**Acceptance Criteria**:
- All media files accessible via S3
- Image metadata preserved
- Post-image associations maintained
- Orphaned images identified

---

#### Task 1.6: Create User Communication Plan
**Priority**: High | **Estimated Effort**: 2 days

**Objectives**:
- Draft communication to members about migration
- Create maintenance page
- Prepare rollback communication

**Deliverables**:
- [ ] Pre-migration announcement email (1 week before)
- [ ] Maintenance mode page HTML
- [ ] Post-migration welcome email
- [ ] Rollback communication template (if needed)
- [ ] FAQ document for common migration questions

**Email Templates Needed**:
1. **T-7 days**: Migration announcement
2. **T-24 hours**: Reminder with downtime window
3. **T-0**: Maintenance mode active
4. **T+1 hour**: Migration complete, test access
5. **T+24 hours**: Welcome to new system

**Acceptance Criteria**:
- All communications reviewed and approved
- Maintenance page tested
- Email templates loaded into system

---

### Phase 2: Sandbox Migration Testing (Complete Dry-Run)

#### Task 2.1: Load Production WordPress Data to Sandbox
**Priority**: Critical | **Estimated Effort**: 2-3 hours

**Objectives**:
- Get recent WordPress backup
- Load into accessible location for sandbox migration
- Verify data integrity

**Steps**:
1. [ ] Create fresh WordPress backup (or use recent backup)
   ```bash
   # On WordPress server
   mysqldump -u root -p wordpress_db > wordpress_backup_sandbox_$(date +%Y%m%d).sql
   
   # Download WordPress files
   tar -czf wordpress_files_sandbox_$(date +%Y%m%d).tar.gz /var/www/html/wp-content/uploads/
   ```

2. [ ] Upload to accessible location for sandbox
   ```bash
   # Upload to S3 or accessible server
   aws s3 cp wordpress_backup_sandbox_*.sql s3://ysc-backups/
   aws s3 cp wordpress_files_sandbox_*.tar.gz s3://ysc-backups/
   ```

3. [ ] Make available to sandbox environment
   - Option A: Load SQL into temporary MySQL/PostgreSQL database
   - Option B: Parse SQL file directly in migration scripts
   - Option C: Download files to sandbox server temporary storage

4. [ ] Verify data counts match production:
   ```sql
   SELECT COUNT(*) FROM wp_users;
   SELECT COUNT(*) FROM wp_posts WHERE post_type = 'post' AND post_status = 'publish';
   SELECT COUNT(*) FROM wp_posts WHERE post_type = 'attachment';
   ```

**Acceptance Criteria**:
- WordPress data accessible from sandbox
- Data counts match production
- SQL file integrity verified
- Media files accessible

---

#### Task 2.2: Execute Complete Migration in Sandbox
**Priority**: Critical | **Estimated Effort**: 4-8 hours

**Objectives**:
- Run all migration scripts in sandbox
- Identify and fix issues
- Validate complete data migration
- Document actual migration time

**Process** (Follow Phase 3 tasks but in sandbox):

1. [ ] Run user migration:
   ```bash
   # Connect to sandbox
   fly ssh console --config etc/fly/fly-sandbox.toml
   
   # Run migration
   mix migrate.users --source=/tmp/wordpress_backup.sql
   ```

2. [ ] Run subscription migration:
   ```bash
   mix migrate.subscriptions --stripe-mode=test
   ```

3. [ ] Run posts migration:
   ```bash
   mix migrate.posts --source=/tmp/wordpress_backup.sql
   ```

4. [ ] Run media migration:
   ```bash
   mix migrate.media --source=/tmp/wordpress_files/ --s3-bucket=ysc-sandbox-media
   ```

5. [ ] Run validation:
   ```bash
   mix migrate.validate --verbose
   ```

**Track Issues**:
- Create a spreadsheet or document tracking:
  - Error messages encountered
  - Data inconsistencies found
  - Missing data or edge cases
  - Performance issues
  - Script improvements needed

**Time Tracking**:
Record actual time for each step:
```
User migration: ___ minutes
Subscription migration: ___ minutes
Posts migration: ___ minutes
Media migration: ___ minutes
Validation: ___ minutes
Total: ___ hours ___ minutes
```

**Acceptance Criteria**:
- All migration scripts complete successfully
- All validation checks pass
- Issues documented with resolutions
- Actual timing recorded
- Scripts updated based on learnings

---

#### Task 2.3: Sandbox Migration Validation
**Priority**: Critical | **Estimated Effort**: 2-3 hours

**Objectives**:
- Thoroughly validate migrated data in sandbox
- Test user experience in sandbox
- Verify integrations work

**Manual Testing Checklist**:

1. [ ] **User Account Testing**
   - [ ] Select 10 random users
   - [ ] Verify profile data correct
   - [ ] Test password reset flow
   - [ ] Test login with reset password
   - [ ] Verify role/permissions correct
   - [ ] Check user dashboard displays correctly

2. [ ] **Subscription Testing**
   - [ ] Test users with active subscriptions
   - [ ] Verify subscription status displays
   - [ ] Check billing dates correct
   - [ ] Verify subscription items correct
   - [ ] Test Stripe test webhook delivery
   - [ ] Verify membership access levels

3. [ ] **Blog Posts Testing**
   - [ ] Check 20 random posts
   - [ ] Verify content formatting preserved
   - [ ] Check images load correctly
   - [ ] Verify featured images display
   - [ ] Test URLs and slugs
   - [ ] Check post dates correct

4. [ ] **Media Library Testing**
   - [ ] Verify images uploaded to S3
   - [ ] Test image processing completed
   - [ ] Check thumbnails generated
   - [ ] Verify image metadata preserved
   - [ ] Test image URLs work

5. [ ] **Integration Testing**
   - [ ] Test Stripe webhooks (test mode)
   - [ ] Test email sending
   - [ ] Test admin functionality
   - [ ] Test booking system (if applicable)
   - [ ] Test any other critical features

**Automated Validation**:
```bash
# Run comprehensive validation
mix migrate.validate --verbose --detailed

# Check data counts
mix migrate.stats

# Verify referential integrity
mix migrate.integrity_check
```

**Create Test Report**:
Document findings in a test report:
```
=== SANDBOX MIGRATION TEST REPORT ===
Date: _______
Environment: Sandbox
WordPress Backup Date: _______

DATA MIGRATION:
✓ Users: 1,234 / 1,234 migrated
✓ Subscriptions: 456 / 456 migrated
✓ Posts: 150 / 150 migrated
✓ Media: 500 / 500 migrated

ISSUES FOUND:
- Issue #1: Description... [FIXED]
- Issue #2: Description... [DOCUMENTED]

USER TESTING:
✓ Login works
✓ Subscriptions display correctly
✓ Blog posts readable
⚠ Minor formatting issue in post #X [LOW PRIORITY]

RECOMMENDATION: 
[ ] READY FOR PRODUCTION MIGRATION
[ ] NEEDS FIXES BEFORE PRODUCTION
```

**Acceptance Criteria**:
- All critical functionality tested
- Test report completed
- All critical issues fixed
- Performance acceptable
- Team signs off on production readiness

---

#### Task 2.4: Refine Migration Scripts Based on Sandbox Learnings
**Priority**: High | **Estimated Effort**: 1-2 days

**Objectives**:
- Fix any issues discovered in sandbox testing
- Optimize scripts for better performance
- Update documentation and procedures

**Common Issues to Address**:
- [ ] Timeout issues (increase batch size or add pagination)
- [ ] Memory issues (reduce batch size, stream data)
- [ ] Data validation failures (add error handling)
- [ ] Missing fields (add default values)
- [ ] Performance problems (optimize queries)
- [ ] Edge cases (add special handling)

**Script Improvements**:
```elixir
# Example: Add better error handling
def migrate_user(wp_user) do
  case create_user(wp_user) do
    {:ok, user} -> 
      Logger.info("Migrated user: #{user.email}")
      {:ok, user}
    
    {:error, changeset} ->
      Logger.error("Failed to migrate user #{wp_user.email}: #{inspect(changeset.errors)}")
      # Continue with next user instead of stopping
      {:error, changeset}
  end
end

# Example: Add progress tracking
def migrate_users(wp_users) do
  total = length(wp_users)
  
  wp_users
  |> Enum.with_index()
  |> Enum.map(fn {wp_user, index} ->
    if rem(index, 100) == 0 do
      Logger.info("Progress: #{index}/#{total} users migrated")
    end
    
    migrate_user(wp_user)
  end)
end
```

**Documentation Updates**:
- [ ] Update migration scripts with better comments
- [ ] Document known issues and workarounds
- [ ] Update estimated timing based on actual results
- [ ] Add troubleshooting section
- [ ] Create runbook for production migration

**Acceptance Criteria**:
- All sandbox issues resolved
- Scripts tested again in sandbox
- Documentation updated
- Production migration plan refined

---

#### Task 2.5: Final Sandbox-to-Production Checklist
**Priority**: Critical | **Estimated Effort**: 1-2 hours

**Objectives**:
- Create detailed production migration runbook
- Verify production environment ready
- Get stakeholder sign-off

**Production Readiness Checklist**:

**Environment**:
- [ ] Production database backed up
- [ ] Production Phoenix app deployed (latest code)
- [ ] Production S3 bucket configured
- [ ] Production Stripe keys configured (live mode)
- [ ] Production environment variables verified
- [ ] DNS TTL reduced to 300 seconds (5 min)

**Scripts & Tools**:
- [ ] All migration scripts tested in sandbox
- [ ] Validation scripts ready
- [ ] Rollback plan documented
- [ ] Emergency contacts identified

**Communication**:
- [ ] User announcement emails drafted
- [ ] Maintenance page ready
- [ ] Support team briefed
- [ ] Stakeholders notified of migration date/time

**Team**:
- [ ] Migration lead identified
- [ ] Backup team member available
- [ ] Support team standing by
- [ ] All team members have access to production

**Timing**:
- [ ] Maintenance window scheduled
- [ ] Based on sandbox timing: Expected ___ hours
- [ ] Buffer added: Plan for ___ hours
- [ ] Rollback decision point identified (e.g., if not done in 4 hours)

**Sign-Off**:
- [ ] Technical team sign-off
- [ ] Business stakeholder sign-off
- [ ] Migration date/time confirmed

**Production Migration Runbook Created**:
Create a step-by-step runbook that can be followed during production migration:
```
PRODUCTION MIGRATION RUNBOOK
Date: _______
Time: _______
Team: _______

PRE-MIGRATION (T-60min):
□ Verify all team members online
□ Verify production backup complete
□ Send "migration starting soon" email

MIGRATION START (T-0):
□ Enable WordPress maintenance mode
□ Verify no users can access site
□ Create final WordPress backup
□ Begin user migration (Expected: X min)
...
```

**Acceptance Criteria**:
- Production runbook complete and reviewed
- All checklist items verified
- Team trained on procedures
- Sign-off obtained
- Ready for production migration

---

### Phase 3: Production Migration Execution (Maintenance Window)

> **Note**: This phase follows the same steps as the sandbox migration (Phase 2, Task 2.2) but executed against production WordPress data and production Phoenix environment.

#### Task 3.1: Enable Maintenance Mode

#### Task 3.1: Enable Maintenance Mode
**Priority**: Critical | **Estimated Effort**: 30 minutes

**Objectives**:
- Take WordPress site offline
- Display maintenance page
- Prevent new data changes

**Steps**:
1. [ ] Enable WordPress maintenance mode plugin
2. [ ] Verify maintenance page displays
3. [ ] Disable WooCommerce checkout
4. [ ] Send "Migration in Progress" email

**Acceptance Criteria**:
- WordPress returns 503 status
- Maintenance page visible to all users
- No new orders or signups possible

---

#### Task 3.2: Create Final WordPress Backup
**Priority**: Critical | **Estimated Effort**: 1 hour

**Objectives**:
- Create point-in-time backup of all WordPress data
- Verify backup integrity

**Steps**:
1. [ ] MySQL dump of entire WordPress database
   ```bash
   mysqldump -u root -p wordpress_db > wordpress_backup_final_$(date +%Y%m%d_%H%M%S).sql
   ```
2. [ ] Tar/zip all WordPress files including uploads
   ```bash
   tar -czf wordpress_files_backup_$(date +%Y%m%d_%H%M%S).tar.gz /var/www/html/
   ```
3. [ ] Upload backups to secure storage (S3)
4. [ ] Verify backup file integrity
5. [ ] Test restore on separate server (if time permits)

**Acceptance Criteria**:
- Database dump complete and verified
- All files backed up
- Backup stored in multiple locations
- Backup integrity confirmed

---

#### Task 3.3: Migrate User Accounts
**Priority**: Critical | **Estimated Effort**: 1-2 hours

**Objectives**:
- Transfer all user accounts to Phoenix
- Preserve user roles and states
- Handle password migration

**Migration Script**: `mix migrate.users`

**Process**:
1. [ ] Read WordPress users table
2. [ ] Extract UltimateMember profile fields
3. [ ] Map WordPress roles to Phoenix roles:
   - `administrator` → `admin`
   - `editor` → `admin` or `board_member`
   - `subscriber` → `member`
   - UltimateMember custom roles → appropriate Phoenix role
4. [ ] Map user states:
   - Active WordPress users → `approved`
   - Pending approval → `pending_approval`
   - Banned/blocked → handle appropriately
5. [ ] Handle passwords:
   - Option A: Force password reset for all users (recommended)
   - Option B: Migrate WordPress password hashes (requires custom authentication logic)
6. [ ] Insert users into Phoenix `users` table
7. [ ] Log any errors or skipped users

**Data Mapping**:
```
WordPress                    → Phoenix
---------------------------------------------
wp_users.user_email         → users.email
wp_users.user_login         → (not used, email is login)
wp_usermeta.first_name      → users.first_name
wp_usermeta.last_name       → users.last_name
um_metadata.phone           → users.phone_number
um_metadata.country         → users.most_connected_country
wp_users.user_registered    → users.inserted_at
wp_capabilities             → users.role (mapped)
um_account_status           → users.state (mapped)
```

**Special Handling**:
- Duplicate emails: Keep newest account, log old one
- Missing required fields: Use defaults or skip with log
- Invalid emails: Fix or skip with notification

**Validation After Migration**:
```elixir
# Verify user count matches
wp_user_count = 1234  # from WordPress
phoenix_user_count = Repo.aggregate(User, :count, :id)

# Verify email uniqueness
duplicate_emails = Repo.all(
  from u in User,
  group_by: u.email,
  having: count(u.id) > 1,
  select: u.email
)
```

**Acceptance Criteria**:
- 100% of valid WordPress users migrated
- User count matches (excluding filtered users)
- No duplicate emails
- All users have `confirmed_at` set or password reset token
- Migration log reviewed for errors

---

#### Task 3.4: Migrate Membership Applications
**Priority**: High | **Estimated Effort**: 1 hour

**Objectives**:
- Transfer UltimateMember form submissions
- Preserve application history
- Link applications to migrated users

**Process**:
1. [ ] Extract UltimateMember form submissions
2. [ ] Map to Phoenix `signup_applications` table
3. [ ] Associate with migrated user accounts
4. [ ] Preserve submission dates
5. [ ] Mark as "Migrated from WordPress" in notes

**Acceptance Criteria**:
- All form submissions preserved
- Applications linked to correct users
- Historical data intact

---

#### Task 3.5: Migrate Stripe Subscriptions
**Priority**: Critical | **Estimated Effort**: 2-3 hours

**Objectives**:
- Create Phoenix subscription records for all active Stripe subscriptions
- Maintain Stripe customer ID associations
- Preserve subscription status and billing dates

**Migration Script**: `mix migrate.subscriptions`

**Process**:
1. [ ] For each user with a Stripe customer ID:
   - Query Stripe API for active subscriptions
   - Create `subscriptions` record
   - Create `subscription_items` records
   - Update user's membership status
2. [ ] Handle subscription states:
   - `active` → insert with current period dates
   - `trialing` → insert with trial end date
   - `past_due` → insert and flag for review
   - `canceled` → record but mark `ends_at`
   - `unpaid` → flag for manual review
3. [ ] Verify subscription metadata
4. [ ] Update MembershipCache for each user

**Stripe API Calls**:
```elixir
# For each migrated user with stripe_customer_id
customer_id = user.stripe_customer_id

{:ok, %{data: subscriptions}} = Stripe.Subscription.list(%{
  customer: customer_id,
  status: "active"
})

Enum.each(subscriptions, fn stripe_sub ->
  Subscriptions.create_subscription(%{
    user_id: user.id,
    stripe_id: stripe_sub.id,
    stripe_status: stripe_sub.status,
    name: stripe_sub.items.data |> List.first() |> get_in([:price, :nickname]),
    current_period_start: DateTime.from_unix!(stripe_sub.current_period_start),
    current_period_end: DateTime.from_unix!(stripe_sub.current_period_end),
    # ... other fields
  })
end)
```

**Special Cases**:
- Users with multiple subscriptions (keep all)
- Cancelled subscriptions with future end date (preserve end_at)
- Subscriptions with coupons/discounts (preserve metadata)
- Corporate/family subscriptions (ensure proper linking)

**Validation**:
```elixir
# Count WordPress/WooCommerce active subscriptions
wp_active_subs = 450  # from WordPress

# Count Phoenix subscriptions
phoenix_subs = Repo.aggregate(
  from(s in Subscription, where: s.stripe_status == "active"),
  :count,
  :id
)

# Verify Stripe matches
{:ok, %{data: stripe_subs}} = Stripe.Subscription.list(%{status: "active", limit: 100})
stripe_count = length(stripe_subs)
```

**Acceptance Criteria**:
- All active Stripe subscriptions have Phoenix records
- Subscription counts match across systems
- No orphaned subscriptions
- Billing dates preserved correctly
- MembershipCache updated

---

#### Task 3.6: Migrate Blog Posts
**Priority**: High | **Estimated Effort**: 1-2 hours

**Objectives**:
- Transfer all published blog posts
- Convert WordPress content to Phoenix format
- Preserve featured images and metadata

**Migration Script**: `mix migrate.posts`

**Process**:
1. [ ] Query WordPress posts:
   ```sql
   SELECT * FROM wp_posts 
   WHERE post_type = 'post' 
   AND post_status IN ('publish', 'draft')
   ORDER BY post_date DESC
   ```
2. [ ] For each post:
   - Extract title, content, excerpt, author
   - Convert post content (HTML cleanup)
   - Generate URL slug from post_name
   - Extract featured image ID
   - Map author (wp_users → Phoenix user)
   - Preserve publish date
3. [ ] Handle post content:
   - Convert WordPress shortcodes (if any)
   - Update image URLs to S3 paths
   - Clean HTML
   - Store as `raw_body` and `rendered_body`
4. [ ] Set post state:
   - `publish` → `published`
   - `draft` → `draft`
   - Set `published_on` from `post_date`
5. [ ] Associate featured images (after media migration)

**Data Mapping**:
```
WordPress                    → Phoenix
---------------------------------------------
wp_posts.post_title         → posts.title
wp_posts.post_content       → posts.raw_body, posts.rendered_body
wp_posts.post_excerpt       → posts.preview_text
wp_posts.post_name          → posts.url_name
wp_posts.post_date          → posts.published_on
wp_posts.post_author        → posts.user_id (map via wp_users)
wp_posts.post_status        → posts.state
wp_postmeta._thumbnail_id   → posts.image_id (after media migration)
```

**Content Transformation**:
```elixir
def transform_content(wordpress_html) do
  wordpress_html
  |> replace_wordpress_shortcodes()
  |> update_image_urls()
  |> sanitize_html()
end

def replace_wordpress_shortcodes(html) do
  # [gallery ids="1,2,3"] → HTML or remove
  # [caption] → <figure> with caption
  # etc.
end

def update_image_urls(html) do
  # https://old-site.com/wp-content/uploads/2023/01/image.jpg
  # → https://your-bucket.s3.amazonaws.com/media/...
end
```

**Validation**:
```elixir
wp_post_count = 150  # from WordPress
phoenix_post_count = Repo.aggregate(Post, :count, :id)

# Check for missing authors
orphan_posts = Repo.all(
  from p in Post,
  left_join: u in User, on: p.user_id == u.id,
  where: is_nil(u.id),
  select: p.id
)
```

**Acceptance Criteria**:
- All published posts migrated
- Post count matches
- Content displays correctly
- Featured images associated (after media migration)
- URLs work with redirects
- No broken internal links

---

#### Task 3.7: Migrate Media Library
**Priority**: High | **Estimated Effort**: 2-3 hours (depending on size)

**Objectives**:
- Upload all WordPress media to S3
- Create Phoenix image records
- Process images (thumbnails, optimization)

**Migration Script**: `mix migrate.media`

**Process**:
1. [ ] Extract WordPress media attachments:
   ```sql
   SELECT 
     p.ID,
     p.post_title,
     p.guid AS url,
     pm1.meta_value AS file_path,
     pm2.meta_value AS alt_text,
     p.post_author
   FROM wp_posts p
   LEFT JOIN wp_postmeta pm1 ON p.ID = pm1.post_id AND pm1.meta_key = '_wp_attached_file'
   LEFT JOIN wp_postmeta pm2 ON p.ID = pm2.post_id AND pm2.meta_key = '_wp_attachment_image_alt'
   WHERE p.post_type = 'attachment'
   AND pm1.meta_value IS NOT NULL
   ```

2. [ ] For each media file:
   - Download from WordPress uploads directory
   - Upload to S3 bucket
   - Create `images` table record
   - Queue for processing (thumbnails, blur hash)
   - Map WordPress attachment ID to Phoenix image ID

3. [ ] S3 Upload Strategy:
   ```elixir
   def upload_to_s3(local_path, wordpress_file_path, user_id) do
     # Generate unique S3 key
     s3_key = "media/#{user_id}/#{unique_filename(wordpress_file_path)}"
     
     # Upload to S3
     ExAws.S3.put_object(bucket, s3_key, File.read!(local_path))
     |> ExAws.request()
     
     # Create image record
     Media.create_image(%{
       user_id: user_id,
       title: extract_title(wordpress_file_path),
       alt_text: alt_text,
       raw_image_path: s3_key,
       processing_state: "unprocessed"
     })
   end
   ```

4. [ ] Queue image processing:
   ```elixir
   # After all uploads, enqueue processing
   images = Repo.all(from i in Image, where: i.processing_state == "unprocessed")
   
   Enum.each(images, fn image ->
     Ysc.Workers.ImageProcessing.new(%{image_id: image.id})
     |> Oban.insert()
   end)
   ```

5. [ ] Create mapping table for WordPress → Phoenix image IDs:
   ```elixir
   # Store in temporary table or file
   %{
     wordpress_attachment_id => phoenix_image_id
   }
   ```

6. [ ] Update post featured images:
   ```elixir
   # After all images uploaded and mapped
   posts_needing_images = get_posts_with_featured_images()
   
   Enum.each(posts_needing_images, fn {post, wp_attachment_id} ->
     phoenix_image_id = mapping[wp_attachment_id]
     
     post
     |> Ecto.Changeset.change(%{image_id: phoenix_image_id})
     |> Repo.update()
   end)
   ```

**Batch Processing**:
- Process in batches of 50-100 images
- Log progress after each batch
- Continue on individual file errors

**Error Handling**:
- Missing files: Log and skip
- Upload failures: Retry 3 times
- Invalid file types: Log and skip

**Validation**:
```elixir
# Count WordPress attachments
wp_attachment_count = 500  # from WordPress

# Count Phoenix images
phoenix_image_count = Repo.aggregate(Image, :count, :id)

# Verify S3 uploads
s3_keys = ExAws.S3.list_objects(bucket, prefix: "media/")
          |> ExAws.request()
          |> elem(1)
          |> Map.get(:body)
          |> Map.get(:contents)
          |> length()

# Check for orphaned images
orphaned_images = Repo.all(
  from i in Image,
  left_join: p in Post, on: p.image_id == i.id,
  where: is_nil(p.id),
  select: count(i.id)
)
```

**Acceptance Criteria**:
- All WordPress media files uploaded to S3
- Image count matches
- Post featured images linked correctly
- Image processing queued
- No broken image URLs

---

#### Task 3.8: Update Post Content Image URLs
**Priority**: Medium | **Estimated Effort**: 1 hour

**Objectives**:
- Replace WordPress image URLs in post content with S3 URLs

**Process**:
1. [ ] For each post with HTML content:
   - Find all `<img>` tags
   - Extract WordPress URLs
   - Map to new S3 URLs using image mapping
   - Update post content
2. [ ] Handle edge cases:
   - External images (leave as-is)
   - Missing images (log warning)
   - Relative URLs

**Acceptance Criteria**:
- All internal image URLs updated
- No broken images in post content
- External images preserved

---

#### Task 3.9: Create WordPress → Phoenix URL Redirects
**Priority**: High | **Estimated Effort**: 1 hour

**Objectives**:
- Preserve SEO by redirecting old WordPress URLs to new Phoenix URLs
- Handle common WordPress URL patterns

**Common WordPress URLs**:
```
WordPress                              → Phoenix
-----------------------------------------------------------------
/blog/2023/01/post-slug/              → /posts/post-slug
/category/category-name/              → /posts (or category page if implemented)
/author/username/                      → (profile or posts by author)
/wp-content/uploads/2023/01/img.jpg   → S3 URL or 404
```

**Implementation Options**:

**Option A: Phoenix Router Redirects**
```elixir
# lib/ysc_web/router.ex
scope "/", YscWeb do
  pipe_through :browser
  
  # Redirect old blog URLs
  get "/blog/:year/:month/:slug", RedirectController, :blog_post
  get "/:year/:month/:slug", RedirectController, :blog_post
  
  # Redirect old media URLs (if not using CDN)
  get "/wp-content/uploads/*path", RedirectController, :media
end
```

**Option B: Nginx/Cloudflare Redirects** (Preferred for performance)
```nginx
# In nginx config or Cloudflare rules
rewrite ^/blog/(\d{4})/(\d{2})/(.*)$ /posts/$3 permanent;
rewrite ^/(\d{4})/(\d{2})/(.*)$ /posts/$3 permanent;
```

**WordPress Post Slug Mapping**:
Create a mapping file or database table:
```elixir
# Store mapping
%{
  "old-wordpress-slug" => "new-phoenix-slug",
  # ...
}

# In controller
def blog_post(conn, %{"slug" => slug}) do
  new_slug = get_mapped_slug(slug) || slug
  redirect(conn, to: ~p"/posts/#{new_slug}")
end
```

**Deliverables**:
- [ ] URL mapping file/table created
- [ ] Redirect rules implemented
- [ ] Test common old URLs
- [ ] Submit updated sitemap to search engines

**Acceptance Criteria**:
- Old WordPress blog URLs redirect to new posts
- 301 (permanent) redirects used
- No redirect loops
- Most common URLs tested

---

#### Task 3.10: Validate Complete Migration
**Priority**: Critical | **Estimated Effort**: 1 hour

**Objectives**:
- Run comprehensive validation checks
- Ensure data integrity across all migrated entities

**Validation Script**: `mix migrate.validate`

**Checks**:
1. [ ] **User Validation**
   ```elixir
   # Count matches
   assert phoenix_user_count == expected_wp_user_count
   
   # No duplicate emails
   assert Repo.aggregate(from(u in User, group_by: u.email, having: count(u.id) > 1), :count) == 0
   
   # All users have required fields
   assert Repo.aggregate(from(u in User, where: is_nil(u.email) or is_nil(u.first_name)), :count) == 0
   ```

2. [ ] **Subscription Validation**
   ```elixir
   # All active subscriptions have Phoenix records
   # Cross-reference with Stripe API
   # Verify billing dates
   # Check subscription item associations
   ```

3. [ ] **Post Validation**
   ```elixir
   # Count matches
   # All posts have valid authors
   # Featured images exist
   # No broken internal links
   # URL slugs are unique
   ```

4. [ ] **Media Validation**
   ```elixir
   # Count matches
   # All S3 uploads successful
   # Images associated with posts
   # No missing files
   ```

5. [ ] **Referential Integrity**
   ```elixir
   # All foreign keys valid
   # No orphaned records
   # All associations resolve
   ```

**Validation Report**:
Generate a detailed report:
```
=== Migration Validation Report ===

Users:
  ✓ Migrated: 1,234 / 1,234
  ✓ No duplicates
  ✓ All required fields present
  ⚠ 5 users missing phone numbers

Subscriptions:
  ✓ Migrated: 456 / 456
  ✓ Stripe sync verified
  ✓ Billing dates preserved

Posts:
  ✓ Migrated: 150 / 150
  ✓ All authors exist
  ⚠ 3 posts missing featured images

Media:
  ✓ Migrated: 500 / 500
  ✓ S3 uploads complete
  ✓ Image processing queued

Overall Status: SUCCESS (with 8 warnings)
```

**Acceptance Criteria**:
- All critical validations pass
- Warnings documented and acceptable
- No data loss detected
- All relationships intact

---

---

### Phase 4: Post-Migration & Go-Live

#### Task 4.1: Launch Phoenix Application
**Priority**: Critical | **Estimated Effort**: 30 minutes

**Steps**:
1. [ ] Deploy latest Phoenix code to production
2. [ ] Run database migrations
3. [ ] Verify application starts successfully
4. [ ] Check critical pages load
5. [ ] Test user login (sample accounts)
6. [ ] Test subscription status display
7. [ ] Verify Stripe webhooks configured

**Smoke Tests**:
- [ ] Homepage loads
- [ ] Login works
- [ ] User dashboard shows subscription
- [ ] Blog posts display
- [ ] Images load from S3
- [ ] Admin panel accessible

**Acceptance Criteria**:
- Application healthy and responsive
- No critical errors in logs
- Sample user accounts work

---

#### Task 4.2: DNS Cutover
**Priority**: Critical | **Estimated Effort**: 30 minutes

**Objectives**:
- Point domain to new Phoenix application
- Monitor DNS propagation

**Steps**:
1. [ ] Update DNS A/CNAME records to point to Fly.io
   ```
   yourdomain.com → your-app.fly.dev
   ```
2. [ ] Reduce TTL before migration (if not already done)
3. [ ] Verify SSL certificate
4. [ ] Monitor DNS propagation (can take up to 48 hours)
5. [ ] Test from multiple locations/networks

**Rollback Plan**:
If critical issues, revert DNS to WordPress:
```
yourdomain.com → old-wordpress-server-ip
```

**Acceptance Criteria**:
- DNS points to Phoenix app
- SSL certificate valid
- Site accessible from multiple locations

---

#### Task 4.3: Configure Stripe Webhooks for New Domain
**Priority**: Critical | **Estimated Effort**: 15 minutes

**Objectives**:
- Update Stripe webhook endpoints to new domain

**Steps**:
1. [ ] Log into Stripe Dashboard
2. [ ] Navigate to Webhooks settings
3. [ ] Update webhook URL:
   ```
   Old: https://old-wordpress-site.com/wc-api/stripe/webhook
   New: https://yourdomain.com/api/stripe/webhook
   ```
4. [ ] Verify webhook secret matches config
5. [ ] Test webhook delivery with Stripe test event
6. [ ] Monitor webhook logs in Phoenix

**Webhook Events Needed**:
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.paid`
- `invoice.payment_failed`
- `checkout.session.completed`

**Acceptance Criteria**:
- Webhooks pointing to Phoenix app
- Test events received successfully
- Webhook signatures verify

---

#### Task 4.4: Send Post-Migration Announcement
**Priority**: High | **Estimated Effort**: 15 minutes

**Steps**:
1. [ ] Send "Welcome to New System" email to all users
2. [ ] Include:
   - Link to new site
   - Instructions for password reset (if needed)
   - What's new/improved
   - Support contact if issues
3. [ ] Post announcement on homepage
4. [ ] Update social media

**Acceptance Criteria**:
- Email sent to all users
- Announcement visible on site

---

#### Task 4.5: Monitor and Address Issues (First 24 Hours)
**Priority**: Critical | **Estimated Effort**: Ongoing

**Objectives**:
- Closely monitor application health
- Address user-reported issues quickly

**Monitoring Checklist**:
- [ ] Application error logs (Fly.io logs)
- [ ] Database performance
- [ ] S3 access patterns
- [ ] Stripe webhook deliveries
- [ ] User login attempts
- [ ] Support email/tickets
- [ ] Social media mentions

**Key Metrics**:
- Response times (should be < 200ms)
- Error rates (should be < 0.1%)
- User complaints (track in spreadsheet)
- Login success rate
- Subscription status accuracy

**Issue Response Plan**:
- Critical (site down): Immediate attention, consider rollback
- High (feature broken): Fix within 2 hours
- Medium (minor bug): Fix within 24 hours
- Low (cosmetic): Add to backlog

**Acceptance Criteria**:
- No critical issues
- High issues resolved within SLA
- User complaints minimal

---

#### Task 4.6: Data Validation Spot Checks
**Priority**: High | **Estimated Effort**: 2-3 hours

**Objectives**:
- Manually verify data for sample users
- Ensure subscription status accurate

**Spot Check Process**:
1. [ ] Select 20 random users across different segments:
   - Active subscribers
   - Cancelled subscriptions
   - Free members
   - Admins
2. [ ] For each user, verify:
   - Profile information correct
   - Email matches WordPress
   - Subscription status matches Stripe
   - Can log in (if password reset sent)
   - Access permissions correct
3. [ ] Check 10 random blog posts:
   - Content displays correctly
   - Images load
   - Formatting preserved
   - Links work
4. [ ] Verify Stripe dashboard:
   - Customer IDs match
   - No duplicate charges
   - Webhooks processing

**Acceptance Criteria**:
- 100% of spot checks pass
- Any discrepancies resolved

---

#### Task 4.7: WordPress Decommissioning
**Priority**: Low | **Estimated Effort**: 1 hour

**Objectives**:
- Archive WordPress site
- Keep as backup for 30-90 days

**Steps**:
1. [ ] Take final WordPress backup
2. [ ] Keep WordPress server running but offline (no DNS)
3. [ ] Set reminder to decommission in 30/60/90 days
4. [ ] Document WordPress backup location
5. [ ] Archive WordPress admin credentials

**Future Decommissioning** (after 30-90 days):
- [ ] Delete WordPress database
- [ ] Remove WordPress files
- [ ] Terminate WordPress server
- [ ] Cancel WordPress hosting

**Acceptance Criteria**:
- WordPress backed up and accessible if needed
- Credentials stored securely
- Decommission reminder set

---

---

### Phase 5: Post-Migration Optimization (Week 1-2)

#### Task 5.1: SEO & Analytics Setup
**Priority**: Medium | **Estimated Effort**: 2-3 hours

**Steps**:
1. [ ] Submit new sitemap to Google Search Console
2. [ ] Set up 301 redirects for all major WordPress URLs
3. [ ] Configure Google Analytics (or alternative)
4. [ ] Update robots.txt
5. [ ] Monitor search rankings
6. [ ] Fix any broken external links

---

#### Task 5.2: Performance Optimization
**Priority**: Medium | **Estimated Effort**: 3-5 hours

**Steps**:
1. [ ] Enable CDN for S3 media (CloudFront)
2. [ ] Optimize database queries (check Ecto logs)
3. [ ] Enable page caching where appropriate
4. [ ] Compress images (if not already done)
5. [ ] Monitor application performance metrics

---

#### Task 5.3: User Feedback Collection
**Priority**: Medium | **Estimated Effort**: 2-3 hours

**Steps**:
1. [ ] Create feedback form on new site
2. [ ] Send survey to users (1 week after migration)
3. [ ] Compile common issues/requests
4. [ ] Prioritize fixes and improvements
5. [ ] Communicate fixes to users

---

#### Task 5.4: Documentation Updates
**Priority**: Low | **Estimated Effort**: 2-3 hours

**Steps**:
1. [ ] Document migration process (lessons learned)
2. [ ] Update user guide/help docs
3. [ ] Create admin guide for new system
4. [ ] Document any manual processes needed

---

## Risk Management

### Critical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Data loss during migration | Low | Critical | Multiple backups, validation scripts, dry runs |
| Extended downtime (>8 hours) | Low | High | Sandbox timing data, thorough testing, clear rollback plan |
| Stripe subscription mismatch | Low | Critical | Extensive validation, Stripe API verification |
| Broken user logins | Medium | High | Password reset emails, support team ready |
| WordPress backup corruption | Low | Critical | Multiple backup copies, integrity checks |
| DNS propagation delays | Medium | Medium | Reduce TTL early, communicate delays |
| Image upload failures | Low | Medium | Batch processing, retry logic, progress tracking |

### Rollback Plan

If critical issues occur during migration:

1. **Stop Migration**: Halt all migration scripts
2. **Restore WordPress**: Re-enable WordPress site
3. **Revert DNS**: Point domain back to WordPress
4. **Notify Users**: Send rollback communication
5. **Analyze Issues**: Determine root cause
6. **Fix and Retry**: Address issues and reschedule migration

**Rollback Decision Criteria**:
- Data corruption detected
- Downtime exceeds 8 hours
- Critical functionality broken (login, payments)
- High volume of user complaints

---

## Success Criteria

The migration is considered successful when:

- [ ] 100% of valid WordPress users migrated
- [ ] 100% of active Stripe subscriptions have Phoenix records
- [ ] All published blog posts migrated with images
- [ ] No data loss detected
- [ ] Site fully functional with all critical features working
- [ ] Users can log in and access their accounts
- [ ] Stripe webhooks processing correctly
- [ ] No increase in error rates
- [ ] User complaints < 5% of user base
- [ ] Downtime within planned maintenance window (< 8 hours)

---

## Timeline Summary

**Week 1-2**: Data assessment, Stripe audit, tooling development (Phase 1)
**Week 3**: Sandbox environment setup and preparation (Phase 1)
**Week 4**: Complete migration dry-run in sandbox, refinement (Phase 2)
**Week 5**: Production migration execution (maintenance window) (Phase 3-4)
**Week 6-7**: Post-migration monitoring and optimization (Phase 5)

**Total Estimated Time**: 6-7 weeks from start to stable production

### Key Milestones

| Milestone | Target Date | Status |
|-----------|-------------|--------|
| Migration scripts complete | Week 2 | ⏳ Pending |
| Sandbox environment ready | Week 3 | ⏳ Pending |
| Sandbox migration complete | Week 4 | ⏳ Pending |
| Production migration approved | End of Week 4 | ⏳ Pending |
| Production migration window | Week 5 | ⏳ Pending |
| Post-migration stable | Week 6 | ⏳ Pending |

### Decision Gates

**Gate 1 (End of Week 2)**: Scripts ready for sandbox testing?
- All Mix tasks created and unit tested
- WordPress data mapping validated
- **GO/NO-GO Decision**

**Gate 2 (End of Week 4)**: Ready for production migration?
- Sandbox migration successful
- All critical issues resolved
- Team trained and ready
- **GO/NO-GO Decision**

**Gate 3 (During Production Migration)**: Continue or rollback?
- If migration exceeds expected time by 50%
- If critical data issues discovered
- **CONTINUE/ROLLBACK Decision**

---

## Team Roles & Responsibilities

**Migration Lead**:
- Overall coordination
- Final decision authority
- Rollback decisions

**Backend Developer(s)**:
- Migration scripts
- Data validation
- Troubleshooting

**DevOps**:
- Infrastructure setup
- Deployment
- DNS changes
- Monitoring

**Support Team**:
- User communication
- Issue tracking
- User assistance post-migration

---

## Tools & Resources Needed

- [ ] Access to WordPress database (MySQL dump)
- [ ] Access to WordPress file system (SSH or FTP)
- [ ] Stripe API keys (test and live)
- [ ] S3 bucket and credentials
- [ ] Staging environment (Fly.io)
- [ ] Email service configured
- [ ] Monitoring tools (logging, alerts)
- [ ] Backup storage (for WordPress archives)

---

## Questions to Answer Before Migration

1. **How many users do we have?**
   - Total users
   - Active subscribers
   - Inactive/suspended accounts

2. **What Stripe subscription products are in use?**
   - Product IDs
   - Price IDs
   - Membership tier mapping

3. **How large is the media library?**
   - Total file count
   - Total file size (GB)
   - Estimated S3 transfer time

4. **What WordPress plugins are in use?**
   - UltimateMember custom fields
   - WooCommerce extensions
   - Any custom integrations

5. **Are there any custom WordPress modifications?**
   - Custom post types
   - Custom user roles
   - Custom database tables

6. **What is the acceptable downtime window?**
   - Time of day
   - Day of week
   - Maximum hours

7. **Do we have a rollback plan approval?**
   - Who decides to rollback?
   - Communication plan if rollback needed

---

## Notes & Assumptions

- WordPress database is accessible and backed up
- All users will need to reset passwords (or we implement WordPress password hash compatibility)
- WordPress site can be taken offline for 4-8 hours
- Staging environment available for testing
- S3 bucket configured and accessible
- Stripe account has API access enabled
- DNS changes can be made quickly (TTL already reduced)
- Email service configured for sending migration notifications

---

## Related Documentation

- [Stripe Webhook Quick Reference](/docs/STRIPE_WEBHOOK_QUICK_REFERENCE.md)
- [Development Architecture](/docs/DEVELOPMENT_ARCHITECTURE.md)
- [New Developer Guide](/docs/NEW_DEVELOPER_GUIDE.md)
- [Troubleshooting Guide](/docs/TROUBLESHOOTING.md)

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-04  
**Author**: Migration Team  
**Status**: Draft - Pending Review
