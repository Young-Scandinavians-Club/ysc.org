defmodule YscWeb.Workers.EventPhotoUploadWorker do
  @moduledoc """
  Uploads event photos or videos to Google Photos (or DevStub in local development).

  The browser uploads directly to S3 (see `YscWeb.EventPhotoUpload`), so this
  worker downloads the object to local scratch space before handing it to the
  Google Photos API client, then removes both the scratch file and (on a
  terminal outcome) the S3 object.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :media,
    max_attempts: 5

  alias Ysc.EventPhotos
  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.Api
  alias Ysc.GooglePhotos.Limits
  alias Ysc.Repo
  alias Ysc.S3Config
  alias Ysc.SafeFile

  @terminal_errors [
    :photo_too_large,
    :video_too_large,
    :file_too_large,
    :filename_too_long,
    :empty_filename,
    :unsupported_type,
    :invalid_path
  ]

  # Google Photos HTTP statuses that a retry cannot clear: the request itself is
  # rejected (malformed), the credentials are bad, the granted scopes don't
  # cover album/media writes, or the target is gone. These need an admin to
  # reconnect the integration or fix the request — hammering them five times
  # just delays the page. 429 (rate limit) and 5xx stay retryable.
  @non_retryable_api_statuses [400, 401, 403, 404]

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{
          "collection_id" => collection_id,
          "s3_key" => s3_key,
          "filename" => filename,
          "user_id" => user_id
        }
      }) do
    final_attempt? = attempt >= max_attempts
    tmp_root = SafeFile.event_photo_tmp_root()
    scratch_id = Ecto.UUID.generate()

    result =
      with {:ok, dest} <-
             SafeFile.event_photo_tmp_path(collection_id, scratch_id, filename),
           :ok <- download_from_s3(s3_key, dest),
           {:ok, stat} <- SafeFile.stat_under_root(tmp_root, dest),
           :ok <- Limits.validate_upload(filename, stat.size),
           collection <-
             EventPhotos.Collection
             |> Repo.get!(collection_id)
             |> Repo.preload(:event),
           {:ok, access_token} <- GooglePhotos.get_access_token(),
           {:ok, _album_id} <-
             Api.ensure_album_and_upload(
               collection,
               collection.event,
               access_token,
               dest,
               filename
             ) do
        Ysc.Logging.info("Event media uploaded",
          collection_id: collection_id,
          event_id: collection.event_id,
          user_id: user_id,
          filename: filename
        )

        :ok
      else
        {:error, reason}
        when reason in @terminal_errors ->
          Ysc.Logging.warning("Event media upload rejected",
            collection_id: collection_id,
            reason: reason,
            filename: filename
          )

          {:error, reason}

        {:error, reason} ->
          log_opts = log_opts_for(collection_id, s3_key, reason)

          cond do
            # Won't come right on its own — discard now rather than burning
            # four more attempts and paging late.
            non_retryable_api_error?(reason) ->
              Ysc.Logging.error(
                "Event media upload discarded: Google Photos rejected the " <>
                  "request and a retry can't fix it",
                log_opts
              )

            # Sentry-visible only once retries are exhausted — a lone transient
            # blip that a retry clears up on its own shouldn't page anyone.
            final_attempt? ->
              Ysc.Logging.error(
                "Event media upload permanently failed after #{max_attempts} attempts",
                log_opts
              )

            true ->
              Ysc.Logging.warning(
                "Event media upload failed, will retry (attempt #{attempt}/#{max_attempts})",
                log_opts
              )
          end

          {:error, reason}
      end

    # cleanup needs the specific terminal-error reason (e.g. to keep
    # :invalid_path off the safe-to-delete list), so that distinction is
    # only collapsed to :ok — telling Oban not to retry — after cleanup runs.
    cleanup(tmp_root, collection_id, scratch_id, filename, s3_key, result)
    oban_result(result)
  end

  # Retry pacing: full jitter, floored at 30s so the five attempts can't all
  # burn out inside two minutes (as they did on 2026-09-08, when Google Photos
  # briefly rejected every album/media write), capped at 10 minutes. The jitter
  # also spreads a single event's photos out instead of retrying them together
  # and re-hitting the same per-user write quota.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    Ysc.Workers.Backoff.full_jitter(attempt, min: 30, cap: 10 * 60)
  end

  defp oban_result({:error, reason}) when reason in @terminal_errors, do: :ok

  defp oban_result({:error, reason} = result) do
    if non_retryable_api_error?(reason), do: {:discard, reason}, else: result
  end

  defp oban_result(result), do: result

  @doc false
  def non_retryable_api_error?({:api_error, status}),
    do: status in @non_retryable_api_statuses

  def non_retryable_api_error?(_), do: false

  defp log_opts_for(
         collection_id,
         s3_key,
         {:s3_download_crashed, e, stacktrace}
       ) do
    [
      collection_id: collection_id,
      s3_key: s3_key,
      error: e,
      stacktrace: stacktrace
    ]
  end

  defp log_opts_for(collection_id, s3_key, reason) do
    [
      collection_id: collection_id,
      s3_key: s3_key,
      reason: describe_reason(reason)
    ]
  end

  # `reason` is the one field forwarded to Sentry (see the handler allowlist in
  # Ysc.Application) — spell the Google Photos failures out so the issue is
  # triageable without digging through Fly logs for the matching request.
  defp describe_reason({:api_error, status}),
    do: "google_photos_api_error http=#{status}"

  defp describe_reason({:s3_download_failed, detail}),
    do: "s3_download_failed #{inspect(detail)}"

  defp describe_reason(reason), do: inspect(reason)

  @download_timeout :timer.minutes(30)

  # Errors that can only occur *after* a successful download (Limits.validate_upload
  # inspecting the real file). Safe to delete the S3 object for these — we've
  # confirmed we could actually read it, it's just not a file we can use.
  @safe_to_delete_after_terminal_error [
    :photo_too_large,
    :video_too_large,
    :file_too_large,
    :filename_too_long,
    :empty_filename,
    :unsupported_type
  ]

  # Fetches the object via its public URL with a plain HTTP GET instead of a
  # signed ExAws.S3 GetObject request.
  #
  # Every object this worker downloads was uploaded through a presigned POST
  # that sets ACL: public-read (see YscWeb.EventPhotoUpload), so an unsigned
  # GET is sufficient and requires no credentials.
  #
  # This isn't a style choice — signed GET requests to the raw Tigris endpoint
  # return 405 in this environment (verified directly against production: PUT,
  # HEAD, and DELETE via ExAws all succeed with normal Tigris responses; GET,
  # signed, ranged or not, consistently 405s with bare, non-Tigris-shaped
  # response headers, on every bucket — something in front of Tigris appears
  # to specifically block signed reads while allowing unsigned public reads
  # through the same virtual-hosted URL). ExAws.S3.download_file/3 also had a
  # separate, real problem: it fans chunks out over Task.async_stream, whose
  # tasks are linked to the caller by default, so a failed chunk crashed this
  # job's process via an EXIT signal that no try/rescue (ExAws's or ours)
  # could catch. Req streams to `dest` directly, so this avoids both issues at
  # once — no signed GET, no linked background tasks.
  # sobelow_skip ["Traversal.FileModule"]
  defp download_from_s3(s3_key, dest) do
    url = S3Config.object_url(s3_key, S3Config.bucket_name())

    opts =
      Keyword.merge(
        [into: File.stream!(dest), receive_timeout: @download_timeout],
        Application.get_env(:ysc, :event_photo_s3_req_opts, [])
      )

    case Req.get(url, opts) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:s3_download_failed, {:http_status, status}}}

      {:error, reason} ->
        {:error, {:s3_download_failed, reason}}
    end
  rescue
    e -> {:error, {:s3_download_crashed, e, __STACKTRACE__}}
  end

  # Always clears the local scratch file (cheap to re-download on retry).
  # Only removes the S3 object when we know it was actually read (a
  # successful upload, or a terminal validation rejection that only happens
  # after reading the file) — never for a download failure, even on the
  # final attempt, since that would permanently destroy a file we never
  # actually got hold of. Those are left in S3 for manual recovery/cleanup.
  defp cleanup(tmp_root, collection_id, scratch_id, filename, s3_key, result) do
    case SafeFile.event_photo_tmp_path(collection_id, scratch_id, filename) do
      {:ok, dest} -> SafeFile.rm_under_root(tmp_root, dest)
      :error -> :ok
    end

    if safe_to_delete_s3?(result) do
      case S3Config.bucket_name()
           |> ExAws.S3.delete_object(s3_key)
           |> ExAws.request() do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Ysc.Logging.warning("Event media S3 object cleanup failed",
            s3_key: s3_key,
            reason: inspect(reason)
          )
      end
    end
  end

  defp safe_to_delete_s3?(:ok), do: true

  defp safe_to_delete_s3?({:error, reason}),
    do: reason in @safe_to_delete_after_terminal_error
end
