# S3 Configuration Migration Summary

This document summarizes the changes made to ensure environment-specific S3 configuration.

## Overview

The codebase was audited and updated to:

1. Remove hardcoded S3 URLs and bucket names
2. Support environment-specific S3 configuration (localstack for dev, AWS S3 for production)
3. Create Terraform configurations for sandbox and production environments

## Changes Made

### 1. New Centralized S3 Configuration Module

**File**: `lib/ysc/s3_config.ex`

A new module provides centralized access to S3 configuration:

- `bucket_name()` - Returns the S3 bucket name from configuration
- `region()` - Returns the AWS region
- `base_url()` - Returns the S3 base URL (localstack for dev/test, AWS for production)
- `object_url(key)` - Constructs the full URL for an S3 object

### 2. Updated Runtime Configuration

**File**: `config/runtime.exs`

Added S3 configuration that reads from environment variables:

- `S3_BUCKET` - S3 bucket name (defaults to "media" for local development)
- `S3_REGION` - AWS region (defaults to "us-west-1")
- `S3_BASE_URL` - Optional custom S3 endpoint URL

Also configures ExAws S3 endpoint:

- Dev/Test: Uses localstack endpoint
- Production: Uses custom endpoint if provided, otherwise default AWS S3

### 3. Updated Files with Hardcoded S3 URLs

The following files were updated to use `Ysc.S3Config` instead of hardcoded values:

1. **lib/ysc_web/components/image_upload_component.ex**

   - Changed: Hardcoded `@s3_bucket "media"` → `S3Config.bucket_name()`
   - Changed: Hardcoded `region: "us-west-1"` → `S3Config.region()`
   - Changed: Hardcoded `url: "http://media.s3.localhost.localstack.cloud:4566"` → `S3Config.base_url()`
   - Changed: URL construction → `S3Config.object_url(details[:key])`

2. **lib/ysc_web/live/admin/admin_post_editor.ex**

   - Same changes as above

3. **lib/ysc_web/live/admin/admin_media_live.ex**

   - Same changes as above

4. **lib/ysc/media.ex**
   - Changed: Hardcoded `@bucket_name "media"` → `S3Config.bucket_name()`
   - Updated `upload_file_to_s3/1` to use `S3Config.bucket_name()`

### 4. Terraform Infrastructure

**Directory**: `terraform/`

Created Terraform configurations for both sandbox and production environments:

#### Sandbox Environment (`terraform/sandbox/`)

- S3 bucket with versioning
- Server-side encryption (AES256)
- CORS configuration
- Public read access for `public/*` objects
- IAM user with appropriate permissions
- IAM access keys

#### Production Environment (`terraform/production/`)

- Same as sandbox, plus:
- Lifecycle rules for cost optimization (transition to Glacier, delete old versions)

## Environment Configuration

### Local Development (Dev/Test)

Uses localstack automatically:

- Bucket: `media` (or from `S3_BUCKET` env var)
- Region: `us-west-1` (or from `S3_REGION` env var)
- Base URL: `http://media.s3.localhost.localstack.cloud:4566`

**No environment variables required** - works out of the box with localstack.

### Sandbox Environment

Set these environment variables:

```bash
export S3_BUCKET=ysc-media-sandbox  # or your sandbox bucket name
export S3_REGION=us-west-1
export S3_BASE_URL=https://ysc-media-sandbox.s3.us-west-1.amazonaws.com  # optional
export AWS_ACCESS_KEY_ID=<from terraform output>
export AWS_SECRET_ACCESS_KEY=<from terraform output>
```

### Production Environment

Set these environment variables:

```bash
export S3_BUCKET=ysc-media-production  # or your production bucket name
export S3_REGION=us-west-1
export S3_BASE_URL=https://ysc-media-production.s3.us-west-1.amazonaws.com  # optional
export AWS_ACCESS_KEY_ID=<from terraform output>
export AWS_SECRET_ACCESS_KEY=<from terraform output>
```

**Note**: If `S3_BASE_URL` is not set, the application will automatically construct the URL from bucket name and region.

## Migration Checklist

- [x] Create centralized S3 configuration module
- [x] Update runtime configuration
- [x] Remove hardcoded S3 URLs from all components
- [x] Remove hardcoded bucket names
- [x] Remove hardcoded regions
- [x] Create Terraform for sandbox
- [x] Create Terraform for production
- [ ] Deploy Terraform to create sandbox resources
- [ ] Deploy Terraform to create production resources
- [ ] Update deployment configuration with environment variables
- [ ] Test in sandbox environment
- [ ] Test in production environment

## Testing

1. **Local Development**: Should continue working with localstack without any changes
2. **Sandbox**: Deploy Terraform, set environment variables, test uploads
3. **Production**: Deploy Terraform, set environment variables, test uploads

## Rollback

If issues occur, you can temporarily revert by:

1. Setting `S3_BUCKET=media` in environment
2. For local dev, the code will automatically use localstack
3. The hardcoded values are preserved in the dev.exs config for ExAws

## Notes

- The bucket name `"media"` is still used as a default for local development
- Production bucket names should be configured via environment variables
- CORS origins in Terraform should be restricted to actual domains in production
- IAM access keys should be stored securely (AWS Secrets Manager, etc.)
