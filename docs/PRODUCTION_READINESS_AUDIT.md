# Production Readiness Audit

This document summarizes the audit and fixes made to ensure the application is production-ready.

## Issues Found and Fixed

### 1. ✅ Hardcoded Email Addresses

**Issue**: Multiple email addresses were hardcoded throughout the codebase.

**Fixed**:

- Created `Ysc.EmailConfig` helper module for centralized email configuration
- Added email configuration to `config/config.exs` with environment variable support
- Updated `YscWeb.Emails.Notifier` to use configurable from email/name
- Updated `YscWeb.Emails.OutageNotification` to use configurable cabin master emails

**Environment Variables Added**:

- `EMAIL_FROM` - Sender email (defaults to "info@ysc.org")
- `EMAIL_FROM_NAME` - Sender name (defaults to "YSC")
- `EMAIL_CONTACT` - General contact (defaults to "info@ysc.org")
- `EMAIL_ADMIN` - Admin email (defaults to "admin@ysc.org")
- `EMAIL_MEMBERSHIP` - Membership email (defaults to "membership@ysc.org")
- `EMAIL_BOARD` - Board email (defaults to "board@ysc.org")
- `EMAIL_VOLUNTEER` - Volunteer email (defaults to "volunteer@ysc.org")
- `EMAIL_TAHOE` - Tahoe cabin email (defaults to "tahoe@ysc.org")
- `EMAIL_CLEAR_LAKE` - Clear Lake cabin email (defaults to "cl@ysc.org")

### 2. ✅ Radar API Key

**Issue**: Radar public key was hardcoded in JavaScript.

**Fixed**:

- Added `RADAR_PUBLIC_KEY` environment variable configuration
- Updated JavaScript to read key from `window.radarPublicKey`
- Added key to both root and admin layouts
- Defaults to test key if not set

### 3. ✅ Stripe Configuration

**Status**: Already properly configured

- Stripe keys are read from environment variables
- Price IDs are environment-specific (production in `config.exs`, test in `dev.exs`)
- No changes needed

### 4. ✅ S3 Configuration

**Status**: Already properly configured

- S3 configuration uses `Ysc.S3Config` module
- Environment variables: `S3_BUCKET`, `S3_REGION`, `S3_BASE_URL`
- Properly handles localstack for dev/test and AWS for production

### 5. ✅ Hostname Configuration

**Status**: Already properly configured

- Base config has `localhost` for development
- Production hostname set via `PHX_HOST` environment variable in `runtime.exs`
- No changes needed

### 6. ✅ AWS Credentials

**Status**: Properly configured

- Makefile has fake credentials for local dev (acceptable)
- Production uses environment variables or IAM roles
- No changes needed

## Remaining Hardcoded Values (Acceptable)

The following hardcoded values are acceptable and don't need to be configurable:

1. **External Service URLs**:

   - `https://js.radar.com`, `https://js.stripe.com` - CDN URLs
   - `https://maps.google.com` - External service URLs
   - `https://ysc.org/...` - External website links

2. **Business Email Addresses in Templates**:

   - Email addresses in HTML templates (contact pages, etc.) are acceptable as they're user-facing
   - Backend email sending now uses configurable addresses

3. **Test/Development Values**:
   - `localhost` in dev configs
   - Test Stripe price IDs in `dev.exs`
   - Fake AWS credentials in Makefile for local dev

## Production Environment Variables Checklist

### Required Variables

- `STRIPE_SECRET` - Stripe secret key
- `STRIPE_PUBLIC_KEY` - Stripe publishable key
- `STRIPE_WEBHOOK_SECRET` - Stripe webhook secret
- `SECRET_KEY_BASE` - Application secret key base
- `DATABASE_URL` - Database connection string
- `PHX_HOST` - Application hostname
- `TURNSTILE_SITE_KEY` - Cloudflare Turnstile site key
- `TURNSTILE_SECRET_KEY` - Cloudflare Turnstile secret key

### Optional Variables (with defaults)

- `RADAR_PUBLIC_KEY` - Radar API key (defaults to test key)
- `EMAIL_FROM` - From email (defaults to "info@ysc.org")
- `EMAIL_FROM_NAME` - From name (defaults to "YSC")
- `EMAIL_CONTACT` - Contact email (defaults to "info@ysc.org")
- `EMAIL_ADMIN` - Admin email (defaults to "admin@ysc.org")
- `EMAIL_MEMBERSHIP` - Membership email (defaults to "membership@ysc.org")
- `EMAIL_BOARD` - Board email (defaults to "board@ysc.org")
- `EMAIL_VOLUNTEER` - Volunteer email (defaults to "volunteer@ysc.org")
- `EMAIL_TAHOE` - Tahoe email (defaults to "tahoe@ysc.org")
- `EMAIL_CLEAR_LAKE` - Clear Lake email (defaults to "cl@ysc.org")
- `S3_BUCKET` - S3 bucket name (defaults to "media")
- `S3_REGION` - AWS region (defaults to "us-west-1")
- `S3_BASE_URL` - S3 base URL (optional, constructed if not set)
- `AWS_ACCESS_KEY_ID` - AWS access key (or use IAM role)
- `AWS_SECRET_ACCESS_KEY` - AWS secret key (or use IAM role)
- `PORT` - Application port (defaults to 4000)
- `POOL_SIZE` - Database pool size (defaults to 10)

## Files Modified

1. `config/config.exs` - Added email and Radar configuration
2. `lib/ysc/email_config.ex` - New helper module for email addresses
3. `lib/ysc_web/emails/notifier.ex` - Updated to use configurable emails
4. `lib/ysc_web/emails/outage_notification.ex` - Updated to use configurable emails
5. `lib/ysc_web/components/layouts/root.html.heex` - Added Radar key script
6. `lib/ysc_web/components/layouts/admin_root.html.heex` - Added Radar key script
7. `assets/js/radar.js` - Updated to read Radar key from window
8. `README.md` - Updated documentation with new environment variables

## Recommendations

1. **Email Templates**: Consider updating email templates to use `Ysc.EmailConfig` helper functions for consistency, though current hardcoded values in templates are acceptable for user-facing content.

2. **Stripe Price IDs**: Consider moving production Stripe price IDs to environment variables for easier management across environments, though current setup (separate config files) is acceptable.

3. **Monitoring**: Ensure all environment variables are properly set in production deployment configuration.

4. **Documentation**: Keep README.md updated as new environment variables are added.
