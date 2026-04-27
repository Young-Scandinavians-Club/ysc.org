defmodule Ysc.S3Config do
  @moduledoc """
  Centralized S3 configuration for different environments.
  Provides environment-specific S3 bucket names, URLs, and regions.
  Uses MinIO for local dev/test and Tigris (S3-compatible) for production.

  ## Public URLs, browser uploads, and presigned GETs (audit)

  **Canonical public object URLs** (links stored in the DB, `<img src>`, etc.) must
  come from `object_url/1` and `object_url/2` so
  `S3_{MEDIA,AVATARS,EXPENSE_REPORTS}_PUBLIC_BASE_URL` apply consistently. Do not
  persist raw `*.fly.storage.tigris.dev` URLs from ExAws response bodies when a
  custom public base is configured.

  In non-sandbox production, configure **all three** public base URLs so uploads,
  links, and CSP prefer your HTTPS hostnames; `*.fly.storage.tigris.dev` is only a
  fallback when any of those are unset (see `include_tigris_virtual_host_in_csp?/0`).

  | Flow | Elixir | JS |
  | ---- | ------ | -- |
  | **Presigned POST** (browser → S3) | `YscWeb.S3.SimpleS3Upload` + `upload_url/0` (media) or `avatars_upload_url/0` (avatars) | `assets/js/uploaders.js` — POST `entry.meta.url` only; no hardcoded host |
  | **Presigned GET** (redirect to private object) | `ExAws.S3.presigned_url/5` via `expense_report_file_presigned_url_args/2` + `YscWeb.ExpenseReportFileController` | n/a — full navigation |
  | **Server `ExAws.S3.Upload`** | `Ysc.Media.upload_file_to_s3/3`, `Ysc.Avatars.upload_to_s3/3` — return `object_url/…` for `location` | n/a |
  | **CSP** | `YscWeb.Plugs.SecurityHeaders` + `storage_csp_connect_sources/0` | n/a |
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
  Optional origin for the expense-reports bucket (e.g. Tigris custom domain).
  Used for public object URLs and presigned GET redirects when configured.

  Must be a full URL with scheme and host, e.g. `https://expenses.example.com` or
  `http://localhost:9000` (non-default ports are preserved for signing). A bare
  hostname or scheme-less value raises when presigned URLs are built.
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
  Whether CSP should still allow `https://*.fly.storage.tigris.dev` (and the raw
  `s3_base_url` when it points at Tigris).

  When **media**, **avatars**, and **expense** public base URLs are all set, browsers
  should only talk to those custom origins for S3-facing flows, so the virtual-host
  wildcard can be omitted for a tighter policy.
  """
  def include_tigris_virtual_host_in_csp? do
    not all_s3_public_origins_configured?()
  end

  defp all_s3_public_origins_configured? do
    nonempty? = fn v -> is_binary(v) and String.trim(v) != "" end

    nonempty?.(media_public_url()) and nonempty?.(avatars_public_url()) and
      nonempty?.(expense_reports_public_url())
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

  **CORS (production):** Direct browser uploads require the S3/Tigris bucket to
  allow your site origin (e.g. `https://...` for `PHX_HOST`) in its CORS policy,
  for both the virtual-hosted `*.fly.storage.tigris.dev` URL and any custom
  domain set via `S3_AVATARS_PUBLIC_BASE_URL`. Tigris custom domains also require
  a CNAME to the bucket host and [DNS-only (not proxied) at Cloudflare](https://www.tigrisdata.com/docs/buckets/custom-domain/)
  so TLS and renewals work.

  Use **one CORS origin per entry** (or one rule per origin). A single field
  like `https://a.example,https://b.example` is often stored as one literal
  origin and **will not match** either site, so uploads fail with CORS in the
  console.

  If the browser posts to `https://<bucket>.fly.storage.tigris.dev`, the public
  base URL is not set in the running app (`S3_AVATARS_PUBLIC_BASE_URL` missing or
  overridden by an empty Fly secret); fixing that is preferred over relying on
  CORS for the virtual host.
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
          tigris_bucket_virtual_host_url(bucket)
        else
          "#{base_url}/#{bucket}"
        end

      _ ->
        tigris_bucket_virtual_host_url(bucket)
    end
  end

  # Fly Tigris virtual-hosted URLs are always https://<bucket>.fly.storage.tigris.dev
  # (scheme / non-default port may come from AWS_ENDPOINT_URL_S3). Do not derive the
  # bucket label from the configured endpoint host: if the endpoint is already virtual-hosted
  # (e.g. .../ysc-prod-avatars.fly.storage.tigris.dev) but this call is for another bucket,
  # String.replace would produce a malformed double subdomain.
  defp tigris_bucket_virtual_host_url(bucket) when is_binary(bucket) do
    {scheme, port_frag} = tigris_scheme_and_port_frag()

    "#{scheme}://#{bucket}.fly.storage.tigris.dev#{port_frag}"
  end

  defp tigris_scheme_and_port_frag do
    case base_url() do
      url when is_binary(url) and url != "" ->
        u = url |> String.trim_trailing("/") |> URI.parse()

        scheme =
          if u.scheme in ["http", "https"], do: u.scheme, else: "https"

        frag =
          case u.port do
            nil -> ""
            80 -> ""
            443 -> ""
            p -> ":#{p}"
          end

        {scheme, frag}

      _ ->
        {"https", ""}
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
              "#{tigris_bucket_virtual_host_url(bucket)}/#{key}"
            else
              "#{base_url}/#{bucket}/#{key}"
            end

          _ ->
            "#{tigris_bucket_virtual_host_url(bucket)}/#{key}"
        end
    end
  end

  @doc """
  Builds arguments for `ExAws.S3.presigned_url/5` for expense report file downloads.

  When `expense_reports_public_url/0` is set (custom domain), uses `bucket_as_host`
  so the signed URL targets that host. The URL's scheme and port are merged into
  the ExAws config so the signature matches non-default ports and `http://` (e.g. MinIO).

  Raises `ArgumentError` if the env value is non-empty but not a valid `http(s)` URL with host.
  """
  def expense_report_file_presigned_url_args(normalized_path, expires_in)
      when is_binary(normalized_path) and is_integer(expires_in) do
    bucket_name = expense_reports_bucket_name()

    default =
      {ExAws.Config.new(:s3), :get, bucket_name, normalized_path,
       [expires_in: expires_in]}

    case expense_reports_public_url() do
      url when is_binary(url) ->
        case parse_public_http_origin!(url) do
          :none ->
            default

          {:ok, %{hostname: host, ex_aws_overrides: overrides}} ->
            config = ExAws.Config.new(:s3, overrides)

            {config, :get, host, normalized_path,
             [
               expires_in: expires_in,
               virtual_host: true,
               bucket_as_host: true
             ]}
        end

      _ ->
        default
    end
  end

  defp parse_public_http_origin!(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" ->
        :none

      true ->
        uri = URI.parse(trimmed)

        cond do
          uri.scheme not in ["http", "https"] ->
            raise ArgumentError,
                  "Invalid S3 public base URL #{inspect(url)}: scheme must be http or https " <>
                    "(got #{inspect(uri.scheme)}). Use a full URL, e.g. https://assets.example.com"

          uri.host in [nil, ""] ->
            raise ArgumentError,
                  "Invalid S3 public base URL #{inspect(url)}: host is required. " <>
                    "Use a full URL with scheme, e.g. https://assets.example.com"

          true ->
            scheme = "#{uri.scheme}://"
            port = uri_effective_port(uri)

            # Explicit `port: nil` clears inherited ExAws :s3 port (e.g. MinIO in test) when the
            # public URL uses the scheme default (443 / 80), so presigned URLs are not signed
            # against the wrong endpoint.
            port_kw =
              if port in [80, 443] do
                [port: nil]
              else
                [port: port]
              end

            overrides = [scheme: scheme, host: uri.host] ++ port_kw

            {:ok,
             %{
               scheme: scheme,
               hostname: uri.host,
               ex_aws_overrides: overrides
             }}
        end
    end
  end

  defp uri_effective_port(%URI{port: port}) when is_integer(port), do: port

  defp uri_effective_port(%URI{scheme: "https"}), do: 443
  defp uri_effective_port(%URI{scheme: "http"}), do: 80
  defp uri_effective_port(%URI{}), do: nil

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
