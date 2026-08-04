defmodule Ysc.GeoIP.DatabaseFetcher do
  @moduledoc """
  Locus custom fetcher that loads GeoLite2-City from the shared app-resources
  S3 bucket. MaxMind downloads are performed only by the weekly CI workflow
  (`etc/scripts/sync_geoip_database.sh`); deployed machines never contact MaxMind.

  All callbacks are failure-tolerant: S3/network/parse errors and unexpected
  exceptions are returned as `{:error, reason}` so locus can retry without
  crashing the application.
  """

  @behaviour :locus_custom_fetcher

  require Ysc.Logging

  alias Ysc.S3Config

  @object_key "geoip/GeoLite2-City.tar.gz"

  @doc false
  def object_key, do: @object_key

  @impl true
  def description(_args) do
    %{
      database_is_stored_remotely: true,
      database_is_fetched_from: {:s3, bucket_name(), @object_key}
    }
  end

  @impl true
  def fetch(_args) do
    case get_database() do
      {:ok, body, modified_on} ->
        {:fetched, success(body, modified_on)}

      {:error, reason} ->
        log_fetch_failure(reason)
        {:error, reason}
    end
  rescue
    error ->
      reason = {:exception, Exception.message(error)}
      log_fetch_failure(reason)
      {:error, reason}
  catch
    kind, reason ->
      wrapped = {kind, reason}
      log_fetch_failure(wrapped)
      {:error, wrapped}
  end

  @impl true
  def conditionally_fetch(args, {:depending_on, previous_metadata}) do
    case fetch(args) do
      {:fetched, %{metadata: %{modified_on: modified_on}} = success} ->
        previous_modified_on = Map.get(previous_metadata, :modified_on)

        if modified_on != :unknown and modified_on == previous_modified_on do
          :dismissed
        else
          {:fetched, success}
        end

      other ->
        other
    end
  rescue
    error ->
      reason = {:exception, Exception.message(error)}
      log_fetch_failure(reason)
      {:error, reason}
  catch
    kind, reason ->
      wrapped = {kind, reason}
      log_fetch_failure(wrapped)
      {:error, wrapped}
  end

  defp success(body, modified_on) do
    %{
      format: :tgz,
      content: body,
      metadata: %{
        fetched_from: {:s3, bucket_name(), @object_key},
        modified_on: modified_on
      }
    }
  end

  defp get_database do
    case Application.get_env(:ysc, :geo_ip_s3_get) do
      fun when is_function(fun, 0) ->
        case fun.() do
          {:ok, body, modified_on} -> {:ok, body, modified_on}
          {:error, reason} -> {:error, reason}
          other -> {:error, {:unexpected_s3_get_result, other}}
        end

      _ ->
        request_from_s3()
    end
  rescue
    error ->
      {:error, {:exception, Exception.message(error)}}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end

  # GeoLite2-City archives are tens of MB; use a longer download window than
  # Req's default timeout. Override via `:ysc, :geo_ip_s3_req_opts`.
  @default_receive_timeout 120_000
  @presigned_url_expires_in 300

  # Fetches via a short-lived presigned URL instead of a signed
  # ExAws.S3.get_object request. ExAws.S3.presigned_url/5 only *builds* a
  # URL (no HTTP request), so it's unaffected by the ExAws.Request.Req
  # GET -> POST rewrite bug that breaks every signed ExAws GET in this
  # environment (see
  # YscWeb.Workers.EventPhotoUploadWorker.download_from_s3/2 for the full
  # story) — this bucket is backend-only/private, so unlike avatars/media/
  # event-photos there's no public URL to fall back to instead.
  defp request_from_s3 do
    bucket = bucket_name()

    with {:ok, url} <-
           ExAws.S3.presigned_url(
             ExAws.Config.new(:s3),
             :get,
             bucket,
             @object_key,
             expires_in: @presigned_url_expires_in
           ),
         {:ok, %Req.Response{status: 200} = resp} <-
           Req.get(url, geo_ip_req_opts()) do
      {:ok, resp.body, modified_on_from_response(resp)}
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      {:error, {:exception, Exception.message(error)}}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end

  defp geo_ip_req_opts do
    Keyword.merge(
      [receive_timeout: @default_receive_timeout],
      Application.get_env(:ysc, :geo_ip_s3_req_opts, [])
    )
  end

  defp bucket_name do
    S3Config.app_resources_bucket_name()
  rescue
    _ -> "app-resources"
  end

  defp log_fetch_failure(reason) do
    # Debug: missing/stale objects and transient S3 errors are expected until CI
    # seeds the bucket, and locus retries on its own. Never escalate to error
    # (which would page via Sentry).
    Ysc.Logging.debug("GeoIP S3 database fetch failed",
      extra: %{
        bucket: bucket_name(),
        key: @object_key,
        reason: inspect(reason)
      }
    )
  rescue
    _ -> :ok
  end

  defp modified_on_from_response(%Req.Response{} = resp) do
    case Req.Response.get_header(resp, "last-modified") do
      [value | _] -> parse_http_date(value)
      _ -> :unknown
    end
  end

  defp parse_http_date(nil), do: :unknown

  defp parse_http_date(value) when is_binary(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{year, month, day}, {hour, minute, second}} ->
        {{year, month, day}, {hour, minute, second}}

      _ ->
        :unknown
    end
  rescue
    _ -> :unknown
  end
end
