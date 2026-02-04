defmodule Ysc.S3Config do
  @moduledoc """
  Centralized S3 configuration for different environments.
  Provides environment-specific S3 bucket names, URLs, and regions.
  Uses Tigris (S3-compatible) storage for production.
  """

  @doc """
  Returns the S3 bucket name for the current environment.
  """
  def bucket_name do
    Application.get_env(:ysc, :s3_bucket, "media")
  end

  @doc """
  Returns the S3 bucket name for expense reports.
  Uses a separate bucket from regular media uploads.

  SECURITY NOTE: This bucket is BACKEND-ONLY.
  - No CORS is configured, preventing direct frontend access
  - All uploads go through the backend (LiveView -> Backend -> S3)
  - Uses backend credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  """
  def expense_reports_bucket_name do
    Application.get_env(:ysc, :expense_reports_s3_bucket, "expense-reports")
  end

  @doc """
  Returns the S3 base URL for the current environment.
  For localstack: http://media.s3.localhost.localstack.cloud:4566
  For production: Uses Tigris endpoint (https://fly.storage.tigris.dev)
  """
  def base_url do
    case Application.get_env(:ysc, :s3_base_url) do
      nil ->
        # Use default based on environment (localstack for dev/test, Tigris for prod)
        default_base_url()

      url ->
        url
    end
  end

  @doc """
  Returns the S3 upload endpoint URL for form uploads.
  For Tigris: Uses virtual-hosted style (https://<bucket-name>.fly.storage.tigris.dev)
  For localstack: Uses the base URL
  """
  def upload_url do
    base = base_url()
    bucket = bucket_name()

    case base do
      url when is_binary(url) and url != "" ->
        base_url = String.trim_trailing(base, "/")
        # Check if this is Tigris endpoint
        if String.contains?(base_url, "tigris.dev") do
          # Tigris virtual-hosted style: https://<bucket-name>.fly.storage.tigris.dev
          base_url
          |> String.replace(
            "fly.storage.tigris.dev",
            "#{bucket}.fly.storage.tigris.dev"
          )
        else
          # Localstack or other custom endpoint
          base_url
        end

      _ ->
        # Fallback: use Tigris virtual-hosted style
        "https://#{bucket}.fly.storage.tigris.dev"
    end
  end

  @doc """
  Returns the region for S3 operations.
  For Tigris, this defaults to "auto" (Tigris handles region automatically).
  """
  def region do
    Application.get_env(:ysc, :s3_region, "auto")
  end

  def aws_access_key_id do
    Application.get_env(:ysc, :aws_access_key_id, "access_key_id")
  end

  def aws_secret_access_key do
    Application.get_env(:ysc, :aws_secret_access_key, "secret_access_key")
  end

  @doc """
  Returns the S3 endpoint configuration for ExAws.
  """
  def endpoint_config do
    case Application.get_env(:ysc, :s3_endpoint) do
      nil -> []
      endpoint_config -> endpoint_config
    end
  end

  @doc """
  Constructs the full URL for an S3 object given a key.
  This is used for constructing the final object URL after upload.
  For Tigris (virtual-hosted style): https://<bucket-name>.fly.storage.tigris.dev/key
  """
  def object_url(key) do
    object_url(key, bucket_name())
  end

  @doc """
  Constructs the full URL for an S3 object given a key and bucket name.
  """
  def object_url(key, bucket) do
    base = base_url()
    key = String.trim_leading(key, "/")

    case base do
      url when is_binary(url) and url != "" ->
        base_url = String.trim_trailing(base, "/")
        # Check if this is Tigris endpoint
        if String.contains?(base_url, "tigris.dev") do
          # Tigris virtual-hosted style: https://<bucket-name>.fly.storage.tigris.dev/key
          # Replace the base endpoint hostname with bucket-prefixed hostname
          # e.g., https://fly.storage.tigris.dev -> https://<bucket>.fly.storage.tigris.dev
          virtual_hosted_url =
            base_url
            |> String.replace(
              "fly.storage.tigris.dev",
              "#{bucket}.fly.storage.tigris.dev"
            )

          "#{virtual_hosted_url}/#{key}"
        else
          # Localstack or other custom endpoint - bucket may be in hostname
          "#{base_url}/#{key}"
        end

      _ ->
        # Fallback: use Tigris virtual-hosted style
        "https://#{bucket}.fly.storage.tigris.dev/#{key}"
    end
  end

  defp default_base_url do
    env = Ysc.Env.current()

    case env do
      :dev ->
        "http://media.s3.localhost.localstack.cloud:4566"

      :test ->
        "http://media.s3.localhost.localstack.cloud:4566"

      _ ->
        # Production - use Tigris endpoint
        "https://fly.storage.tigris.dev"
    end
  end
end
