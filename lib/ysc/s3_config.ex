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
  Optional HTTPS origin for the media bucket (e.g. Tigris custom domain).
  When set, `upload_url/0` and public `object_url/1` use this host instead of
  `*.fly.storage.tigris.dev`.
  """
  def media_public_url do
    Application.get_env(:ysc, :s3_media_public_url)
  end

  @doc """
  Optional HTTPS origin for the avatars bucket (e.g. Tigris custom domain).
  """
  def avatars_public_url do
    Application.get_env(:ysc, :s3_avatars_public_url)
  end

  @doc """
  Optional HTTPS origin for the expense-reports bucket (e.g. Tigris custom domain).
  Used for public object URLs and presigned GET redirects when configured.
  """
  def expense_reports_public_url do
    Application.get_env(:ysc, :s3_expense_reports_public_url)
  end

  @doc """
  Origins to add to CSP `connect-src` so LiveView S3 XHR uploads can reach custom domains.
  """
  def storage_csp_connect_sources do
    [media_public_url(), avatars_public_url(), expense_reports_public_url()]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.map(&csp_connect_origin/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp csp_connect_origin(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port}
      when scheme in ["http", "https"] and is_binary(host) ->
        if port && port not in [nil, 80, 443] do
          "#{scheme}://#{host}:#{port}"
        else
          "#{scheme}://#{host}"
        end

      _ ->
        nil
    end
  end

  defp public_object_base_for_bucket(bucket) do
    cond do
      bucket == bucket_name() -> media_public_url()
      bucket == avatars_bucket_name() -> avatars_public_url()
      bucket == expense_reports_bucket_name() -> expense_reports_public_url()
      true -> nil
    end
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
    case media_public_url() do
      url when is_binary(url) and url != "" ->
        String.trim_trailing(url, "/")

      _ ->
        virtual_host_upload_endpoint(bucket_name())
    end
  end

  @doc """
  Upload endpoint for the avatars bucket (presigned POST / XHR), respecting
  `s3_avatars_public_url` when set.
  """
  def avatars_upload_url do
    case avatars_public_url() do
      url when is_binary(url) and url != "" ->
        String.trim_trailing(url, "/")

      _ ->
        virtual_host_upload_endpoint(avatars_bucket_name())
    end
  end

  defp virtual_host_upload_endpoint(bucket) do
    base = base_url()

    case base do
      url when is_binary(url) and url != "" ->
        base_url = String.trim_trailing(url, "/")

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
    url = base_url()
    is_binary(url) && String.contains?(url, "tigris.dev")
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
    key = String.trim_leading(key, "/")

    case public_object_base_for_bucket(bucket) do
      origin when is_binary(origin) and origin != "" ->
        "#{String.trim_trailing(origin, "/")}/#{key}"

      _ ->
        base = base_url()

        case base do
          url when is_binary(url) and url != "" ->
            base_url = String.trim_trailing(url, "/")

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
  end

  @doc """
  Builds arguments for `ExAws.S3.presigned_url/5` for expense report file downloads.

  When `expense_reports_public_url/0` is set (custom domain), uses `bucket_as_host`
  so the signed URL targets that host.
  """
  def expense_report_file_presigned_url_args(normalized_path, expires_in)
      when is_binary(normalized_path) and is_integer(expires_in) do
    config = ExAws.Config.new(:s3)
    bucket_name = expense_reports_bucket_name()

    case expense_reports_public_url() do
      url when is_binary(url) and url != "" ->
        case URI.parse(url) do
          %URI{host: host} when is_binary(host) ->
            {config, :get, host, normalized_path,
             [
               expires_in: expires_in,
               virtual_host: true,
               bucket_as_host: true
             ]}

          _ ->
            {config, :get, bucket_name, normalized_path,
             [expires_in: expires_in]}
        end

      _ ->
        {config, :get, bucket_name, normalized_path, [expires_in: expires_in]}
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
