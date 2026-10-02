defmodule YscWeb.AvatarUpload do
  @moduledoc """
  Shared helpers for LiveView avatar direct-to-S3 uploads.
  """

  import Phoenix.LiveView, only: [consume_uploaded_entries: 3]

  alias Ysc.Accounts.User
  alias Ysc.Avatars
  alias Ysc.S3Config
  alias YscWeb.S3.DirectUpload

  @allowed_extensions ~w(.jpg .jpeg .png .webp .gif)

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

    DirectUpload.presign(socket,
      kind: :avatars,
      key: key,
      content_type: Avatars.content_type_for_extension(ext),
      max_file_size: socket.assigns.uploads[upload_name].max_file_size
    )
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
