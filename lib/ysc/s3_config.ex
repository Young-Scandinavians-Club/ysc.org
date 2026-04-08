defmodule Ysc.S3Config do
  @moduledoc """
  Centralized S3 configuration for different environments.
  Provides environment-specific S3 bucket names, URLs, and regions.
  Uses MinIO for local dev/test and Tigris (S3-compatible) for production.
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
  Returns the S3 bucket name for user avatars.
  """
  def avatars_bucket_name do
    Application.get_env(:ysc, :avatars_s3_bucket, "avatars")
  end

  @doc """
  Returns the S3 base URL for the current environment.
  For MinIO (dev/test): http://localhost:9000
  For production: Uses Tigris endpoint (https://fly.storage.tigris.dev)
  """
  def base_url do
    case Application.get_env(:ysc, :s3_base_url) do
      nil ->
        default_base_url()

      url ->
        url
    end
  end

  @doc """
  Returns the S3 upload endpoint URL for form uploads.
  For Tigris: Uses virtual-hosted style (https://<bucket-name>.fly.storage.tigris.dev)
  For MinIO: Uses path-style (http://localhost:9000/<bucket>)
  """
  def upload_url do
    base = base_url()
    bucket = bucket_name()

    case base do
      url when is_binary(url) and url != "" ->
        base_url = String.trim_trailing(base, "/")

        if String.contains?(base_url, "tigris.dev") do
          base_url
          |> String.replace(
            "fly.storage.tigris.dev",
            "#{bucket}.fly.storage.tigris.dev"
          )
        else
          "#{base_url}/#{bucket}"
        end

      _ ->
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
  Returns whether server-side encryption (SSE-S3/AES256) should be requested
  on uploads. MinIO does not support SSE without KMS, so this is disabled
  outside of production (Tigris) where SSE is available by default.
  """
  def server_side_encryption? do
    base_url()
    |> String.contains?("tigris.dev")
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

        if String.contains?(base_url, "tigris.dev") do
          virtual_hosted_url =
            base_url
            |> String.replace(
              "fly.storage.tigris.dev",
              "#{bucket}.fly.storage.tigris.dev"
            )

          "#{virtual_hosted_url}/#{key}"
        else
          "#{base_url}/#{bucket}/#{key}"
        end

      _ ->
        "https://#{bucket}.fly.storage.tigris.dev/#{key}"
    end
  end

  defp default_base_url do
    env = Ysc.Env.current()

    case env do
      :dev ->
        "http://localhost:9000"

      :test ->
        "http://localhost:9000"

      _ ->
        "https://fly.storage.tigris.dev"
    end
  end
end
