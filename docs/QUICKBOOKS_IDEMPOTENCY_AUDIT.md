# QuickBooks Idempotency Audit & Strategy

## Overview

This document outlines the idempotency management and recovery strategy for all QuickBooks API interactions in the codebase.

## Idempotency Mechanisms

### 1. QuickBooks Native Idempotency (`requestid` Parameter)

QuickBooks Online supports native idempotency via the `requestid` query parameter. When a request with a `requestid` is retried, QuickBooks will replay the original response instead of creating a duplicate object.

**Scope**: The ID must be unique per Company (Realm ID).

**Implementation**: All create operations now support an `opts` parameter with `idempotency_key` or `requestid` option.

### 2. Application-Level Idempotency

For critical operations, we also implement application-level checks:
- Database checks for existing records
- "Get or Create" patterns
- Immediate storage of created IDs

## Operations Audit

### ✅ Create Operations (All Support Idempotency)

#### 1. `create_bill/2`
- **Status**: ✅ Fully implemented
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: `"expense_report_#{expense_report.id}"`
- **Application Check**: Checks for existing `bill_id` in database before creation
- **Recovery**: Stores `bill_id` immediately after creation, even if receipt upload fails
- **Location**: `lib/ysc/expense_reports/quickbooks_sync.ex`

#### 2. `create_sales_receipt/2`
- **Status**: ✅ Idempotency support added
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: Should be based on payment/transaction ID
- **Recovery**: Token refresh retry with same idempotency key
- **Location**: `lib/ysc/quickbooks/client.ex:125`

#### 3. `create_refund_receipt/2`
- **Status**: ✅ Idempotency support added
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: Should be based on refund/transaction ID
- **Recovery**: Token refresh retry with same idempotency key
- **Location**: `lib/ysc/quickbooks/client.ex:242`

#### 4. `create_deposit/2`
- **Status**: ✅ Idempotency support added
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: Should be based on payout/transaction ID
- **Recovery**: Token refresh retry with same idempotency key
- **Location**: `lib/ysc/quickbooks/client.ex:377`

#### 5. `create_customer/2`
- **Status**: ✅ Idempotency support added
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: Should be based on user/customer ID
- **Recovery**: Token refresh retry with same idempotency key
- **Location**: `lib/ysc/quickbooks/client.ex:503`

#### 6. `create_vendor/2`
- **Status**: ✅ Idempotency support added
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: Should be based on user/vendor ID
- **Application Check**: `get_or_create_vendor/2` checks for existing vendor by email first
- **Recovery**: Handles duplicate name errors and extracts existing vendor ID
- **Location**: `lib/ysc/quickbooks/client.ex:2738`

#### 7. `create_item/2` (private)
- **Status**: ✅ Idempotency support added
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: Should be based on item name or ID
- **Application Check**: `get_or_create_item/2` checks for existing item by name first
- **Recovery**: Token refresh retry with same idempotency key
- **Location**: `lib/ysc/quickbooks/client.ex:825`

#### 8. `upload_attachment/4`
- **Status**: ✅ Idempotency support added
- **Idempotency**: Uses `requestid` parameter
- **Key Format**: Should be based on file path or S3 key
- **Recovery**: Token refresh retry with same idempotency key
- **Location**: `lib/ysc/quickbooks/client.ex:3136`

### ⚠️ Update Operations

#### 1. `link_attachment_to_bill/2`
- **Status**: ⚠️ No idempotency needed (idempotent by design)
- **Reason**: Uses PUT operation with specific attachable ID and bill ID
- **Recovery**: Token refresh retry
- **Location**: `lib/ysc/quickbooks/client.ex:3432`

### ✅ Query Operations (Read-Only)

All query operations are naturally idempotent (read-only):
- `query_account_by_name/1`
- `query_class_by_name/1`
- `query_vendor_by_email/2`
- `query_vendor_by_display_name/1`
- `query_item_by_name/1`

## Recovery Mechanisms

### 1. Token Refresh Retry
All operations automatically retry once with a refreshed token if they receive a 401 response. The retry uses the same URL (including idempotency key) to ensure idempotency.

### 2. Error Handling
- **401 Unauthorized**: Automatic token refresh and retry
- **Duplicate Errors**: Special handling for vendor duplicate name errors
- **Network Errors**: Logged and returned as `:request_failed`

### 3. Application-Level Recovery

#### Expense Report Sync
- **Database Lock**: Uses `FOR UPDATE NOWAIT` to prevent concurrent processing
- **Idempotency Check**: Checks for existing `bill_id` before creating
- **Immediate Storage**: Stores `bill_id` immediately after creation
- **Graceful Degradation**: Receipt upload failures don't fail the entire sync

#### Vendor Creation
- **Pre-check**: Queries for existing vendor by email before creating
- **Duplicate Handling**: Extracts vendor ID from duplicate name errors
- **Retry Logic**: Retries with modified display name if duplicate

#### Item Creation
- **Pre-check**: Queries for existing item by name before creating
- **Cache**: Caches item IDs to avoid repeated queries

## Best Practices

### Idempotency Key Format

Recommended formats for idempotency keys:

1. **Bills**: `"expense_report_#{expense_report_id}"`
2. **Sales Receipts**: `"payment_#{payment_id}"` or `"txn_#{transaction_id}"`
3. **Refund Receipts**: `"refund_#{refund_id}"`
4. **Deposits**: `"payout_#{payout_id}"` or `"deposit_#{deposit_id}"`
5. **Customers**: `"customer_#{user_id}"` or `"user_#{user_id}"`
6. **Vendors**: `"vendor_#{user_id}"` or `"user_#{user_id}"`
7. **Items**: `"item_#{item_name}"` (normalized)
8. **Attachments**: `"attachment_#{s3_path_hash}"` or `"attachment_#{expense_item_id}"`

### When to Use Idempotency Keys

**Always use idempotency keys for:**
- Operations triggered by external events (webhooks, payments)
- Operations that can be retried (Oban jobs, background workers)
- Operations that create financial records (bills, receipts, deposits)

**Optional for:**
- One-time setup operations
- Operations with built-in "get or create" logic (if the check is reliable)

### Error Recovery Strategy

1. **Network Errors**: Retry with same idempotency key
2. **401 Errors**: Refresh token and retry with same idempotency key
3. **Duplicate Errors**: Extract existing ID from error response when possible
4. **Validation Errors**: Don't retry (fix the data first)

## Testing Recommendations

1. **Idempotency Tests**: Verify that retrying with the same key returns the same result
2. **Concurrency Tests**: Verify that concurrent requests with the same key don't create duplicates
3. **Recovery Tests**: Verify that operations recover correctly after failures
4. **Token Refresh Tests**: Verify that token refresh retries maintain idempotency

## Future Improvements

1. **Centralized Idempotency Key Generation**: Create a helper function for consistent key formats
2. **Idempotency Key Storage**: Store idempotency keys in database to track retries
3. **Automatic Retry Logic**: Add exponential backoff for transient failures
4. **Idempotency Key Validation**: Validate key format and uniqueness

## References

- [QuickBooks API Documentation - Idempotency](https://developer.intuit.com/app/developer/qbo/docs/develop/authentication-and-authorization/oauth-2.0#idempotency)
- QuickBooks uses `requestid` query parameter for idempotency
- Scope: Unique per Company (Realm ID)

