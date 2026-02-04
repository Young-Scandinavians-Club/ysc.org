# S3 Credentials Configuration for Expense Reports

## Overview

This document outlines the S3 credentials configuration for downloading expense report receipts/evidence from S3 (or S3-compatible storage like Tigris).

## Configuration

### Environment Variables

The application uses the following environment variables for S3 access:

- `AWS_ACCESS_KEY_ID` - Access key ID for S3 operations
- `AWS_SECRET_ACCESS_KEY` - Secret access key for S3 operations
- `EXPENSE_REPORTS_BUCKET_NAME` - Bucket name for expense reports (defaults to "expense-reports")
- `AWS_ENDPOINT_URL_S3` - S3 endpoint URL (for Tigris or other S3-compatible storage)
- `AWS_REGION` - AWS region (defaults to "auto" for Tigris)

### ExAws Configuration

ExAws is configured in `config/runtime.exs` to use system environment variables:

```elixir
config :ex_aws,
  debug_requests: false,
  json_codec: Jason,
  access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
  secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}
```

**Important**: These credentials are used for ALL S3 operations, including:
- Media bucket uploads/downloads
- Expense reports bucket uploads/downloads

### Required Permissions

The AWS credentials must have the following permissions:

#### For Expense Reports Bucket

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::expense-reports/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::expense-reports"
    }
  ]
}
```

#### For Media Bucket (if using same credentials)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::media/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::media"
    }
  ]
}
```

## Download Operations

### Expense Report Receipt Downloads

The `download_from_s3_to_temp/1` function in `lib/ysc/expense_reports/quickbooks_sync.ex` downloads receipts from S3:

1. **Uses ExAws**: All downloads use `ExAws.S3.get_object/2` which automatically uses the configured credentials
2. **Bucket**: Uses `S3Config.expense_reports_bucket_name()` to get the correct bucket
3. **Credentials**: Automatically uses `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from environment

### Code Location

```elixir
# lib/ysc/expense_reports/quickbooks_sync.ex
defp download_from_s3_to_temp(s3_path) do
  bucket = S3Config.expense_reports_bucket_name()
  key = extract_s3_key(s3_path)

  # ExAws automatically uses credentials from runtime.exs configuration
  case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
    {:ok, %{body: body}} ->
      # ... save to temp file
    {:error, reason} ->
      # ... handle error
  end
end
```

## Verification

### Check Configuration

The download function logs configuration status:

```elixir
Logger.debug("[QB Expense Sync] download_from_s3_to_temp: ExAws configuration check",
  bucket: bucket,
  access_key_id_configured: !is_nil(access_key_id),
  secret_access_key_configured: secret_access_key_configured
)
```

### Common Issues

1. **Access Denied Errors**
   - Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set
   - Verify credentials have read permissions for the expense-reports bucket
   - Check bucket name matches `EXPENSE_REPORTS_BUCKET_NAME` environment variable

2. **Connection Errors**
   - Verify `AWS_ENDPOINT_URL_S3` is set correctly (for Tigris or custom endpoints)
   - For localstack: Ensure localstack is running and accessible

3. **Missing Credentials**
   - Check environment variables are loaded at runtime
   - Verify `config/runtime.exs` is being executed
   - Check application logs for credential configuration status

## Environment-Specific Configuration

### Development (Localstack)

```elixir
# config/dev.exs
config :ex_aws,
  access_key_id: "dummy",
  secret_access_key: "fake",
  s3: [
    scheme: "http://",
    host: "media.s3.localhost.localstack.cloud",
    port: "4566"
  ]
```

### Production (Tigris)

```bash
export AWS_ACCESS_KEY_ID=<your-tigris-access-key>
export AWS_SECRET_ACCESS_KEY=<your-tigris-secret-key>
export EXPENSE_REPORTS_BUCKET_NAME=expense-reports
export AWS_ENDPOINT_URL_S3=https://fly.storage.tigris.dev
export AWS_REGION=auto
```

## Security Notes

1. **Backend-Only Access**: The expense-reports bucket is backend-only:
   - No CORS configuration (prevents direct frontend access)
   - All uploads go through the backend
   - Downloads are performed server-side only

2. **Credential Storage**:
   - Credentials are stored as environment variables
   - Never commit credentials to version control
   - Use secret management systems in production (e.g., Fly secrets, AWS Secrets Manager)

3. **Least Privilege**:
   - Use separate credentials for different buckets if needed
   - Grant only necessary permissions (read for downloads, write for uploads)
   - Rotate credentials regularly

## Testing

To verify credentials are working:

```elixir
# In IEx
alias Ysc.ExpenseReports.QuickbooksSync

# Test download (replace with actual S3 path)
s3_path = "receipts/1234567890_receipt.pdf"
case QuickbooksSync.download_from_s3_to_temp(s3_path) do
  {:ok, temp_file} ->
    IO.puts("Success! Downloaded to: #{temp_file}")
    File.rm(temp_file)
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## References

- ExAws Documentation: https://hexdocs.pm/ex_aws/
- S3Config Module: `lib/ysc/s3_config.ex`
- QuickBooks Sync: `lib/ysc/expense_reports/quickbooks_sync.ex`
- Runtime Configuration: `config/runtime.exs`

