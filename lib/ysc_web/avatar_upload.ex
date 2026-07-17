defmodule YscWeb.AvatarUpload do
  @moduledoc """
  Shared helpers for LiveView avatar direct-to-S3 uploads.
  """

  import Phoenix.LiveView, only: [consume_uploaded_entries: 3]

  alias Ysc.Accounts.User
  alias Ysc.Avatars
  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  @allowed_extensions ~w(.jpg .jpeg .png .webp .gif .svg)

  @doc """
  Presigns a direct avatar upload using a server-controlled content type.
  """
  def presign(entry, socket, %User{} = user, upload_name \\ :avatar) do
    avatar_id = Ecto.ULID.generate()

    ext =
      entry.client_name
      |> Path.extname()
      |> String.downcase()
      |> then(fn e ->
        if e in @allowed_extensions, do: e, else: ".webp"
      end)

    key = "#{user.id}/#{avatar_id}/original#{ext}"

    config = %{
      region: S3Config.region(),
      access_key_id: S3Config.aws_access_key_id(),
      secret_access_key: S3Config.aws_secret_access_key()
    }

    max_file_size = socket.assigns.uploads[upload_name].max_file_size

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(config, S3Config.avatars_bucket_name(),
        key: key,
        content_type: Avatars.content_type_for_extension(ext),
        max_file_size: max_file_size,
        expires_in: :timer.hours(1),
        server_side_encryption: S3Config.server_side_encryption?()
      )

    upload_url = S3Config.avatars_upload_url()
    :ok = S3Config.assert_direct_upload_url!(upload_url, :avatars)

    meta = %{
      uploader: "S3",
      key: key,
      url: upload_url,
      fields: fields
    }

    {:ok, meta, socket}
  end

  @doc """
  Consumes uploaded avatar entries and creates avatar records with processing jobs.
  """
  def consume(socket, %User{} = user, upload_name \\ :avatar) do
    consume_uploaded_entries(socket, upload_name, fn meta, _entry ->
      case consume_upload_meta(user, meta) do
        {:ok, avatar} -> {:ok, avatar}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc false
  def consume_upload_meta(%User{} = user, %{key: key}) do
    location = S3Config.object_url(key, S3Config.avatars_bucket_name())

    case Avatars.create_avatar_and_enqueue_job(user, %{
           source: :upload,
           original_path: location
         }) do
      {:ok, avatar} -> {:ok, avatar}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns true when at least one consumed upload succeeded.
  """
  def upload_succeeded?(outcomes),
    do: Enum.any?(outcomes, &match?({:ok, _}, &1))

  @doc """
  Returns true when at least one consumed upload failed.
  """
  def upload_failed?(outcomes),
    do: Enum.any?(outcomes, &match?({:error, _}, &1))
end
