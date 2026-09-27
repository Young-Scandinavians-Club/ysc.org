defmodule YscWeb.S3.DirectUpload do
  @moduledoc """
  Shared LiveView presign helper for browser direct-to-S3 uploads.

  Avatar, media-library, and event-photo uploads all need the same SigV4 POST
  fields plus Phoenix LiveView's `external` uploader meta (`uploader`, `key`,
  `url`, `fields`). Call this instead of assembling `SimpleS3Upload` and
  `S3Config` credentials by hand.

  ## Examples

      DirectUpload.presign(socket,
        kind: :media,
        key: "event_photo_uploads/collection-id/unique.jpg",
        content_type: "image/jpeg",
        max_file_size: socket.assigns.uploads.photos.max_file_size
      )
  """

  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  @default_expires_in :timer.hours(1)

  @doc """
  Presigns a LiveView direct-to-S3 upload.

  ## Options

    * `:kind` — `:media` or `:avatars` (required)
    * `:key` — object key (required)
    * `:content_type` — MIME type signed into the POST policy (required)
    * `:max_file_size` — maximum bytes allowed by the policy (required)
    * `:expires_in` — milliseconds until the signed POST expires
      (default: 1 hour)

  Returns `{:ok, meta, socket}` where `meta` is the map Phoenix LiveView's
  external S3 uploader expects.
  """
  def presign(socket, opts) when is_list(opts) do
    key = Keyword.fetch!(opts, :key)
    content_type = Keyword.fetch!(opts, :content_type)
    max_file_size = Keyword.fetch!(opts, :max_file_size)
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)

    {bucket, upload_url, kind} =
      case Keyword.fetch!(opts, :kind) do
        :media ->
          {S3Config.bucket_name(), S3Config.upload_url(), :media}

        :avatars ->
          {S3Config.avatars_bucket_name(), S3Config.avatars_upload_url(),
           :avatars}

        other ->
          raise ArgumentError,
                "unsupported DirectUpload kind: #{inspect(other)} (expected :media or :avatars)"
      end

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(credentials(), bucket,
        key: key,
        content_type: content_type,
        max_file_size: max_file_size,
        expires_in: expires_in,
        server_side_encryption: S3Config.server_side_encryption?()
      )

    :ok = S3Config.assert_direct_upload_url!(upload_url, kind)

    meta = %{
      uploader: "S3",
      key: key,
      url: upload_url,
      fields: fields
    }

    {:ok, meta, socket}
  end

  @doc """
  SigV4 credentials map consumed by `SimpleS3Upload.sign_form_upload/3`.
  """
  def credentials do
    %{
      region: S3Config.region(),
      access_key_id: S3Config.aws_access_key_id(),
      secret_access_key: S3Config.aws_secret_access_key()
    }
  end
end
