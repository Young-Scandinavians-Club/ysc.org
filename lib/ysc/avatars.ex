defmodule Ysc.Avatars do
  @moduledoc """
  Context for managing user avatars.

  Handles avatar creation, library retrieval, selection, S3 uploads,
  and OAuth profile image synchronization.
  """
  require Ysc.Logging

  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Avatars.Avatar
  alias Ysc.Accounts.User
  alias Ysc.S3Config

  @doc """
  Creates a new avatar record for the given user.
  The `user_id` is set explicitly (not via cast) for security.
  """
  def create_avatar(%User{} = user, attrs) do
    %Avatar{}
    |> Avatar.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
  end

  @doc """
  Returns all avatars for a user that have completed processing, most recent first.
  """
  def list_user_avatars(%User{} = user) do
    from(a in Avatar,
      where: a.user_id == ^user.id and a.processing_state == :completed,
      order_by: [desc: a.inserted_at, desc: a.id]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single avatar by ID. Returns nil if not found.
  """
  def get_avatar(id), do: Repo.get(Avatar, id)

  @doc """
  Gets a single avatar by ID, raises if not found.
  """
  def get_avatar!(id), do: Repo.get!(Avatar, id)

  @doc """
  Sets the user's current avatar. Verifies the avatar belongs to the user.
  """
  def set_current_avatar(%User{} = user, avatar_id) do
    case Repo.get(Avatar, avatar_id) do
      nil ->
        {:error, :not_found}

      avatar ->
        if avatar.user_id == user.id do
          user
          |> Ecto.Changeset.change(current_avatar_id: avatar.id)
          |> Repo.update()
        else
          {:error, :not_owner}
        end
    end
  end

  @doc """
  Clears the user's current avatar (resets to default).
  """
  def clear_current_avatar(%User{} = user) do
    user
    |> Ecto.Changeset.change(current_avatar_id: nil)
    |> Repo.update()
  end

  @doc """
  Updates the processing state and paths on an avatar after processing.
  """
  def update_processed_avatar(%Avatar{} = avatar, attrs) do
    avatar
    |> Avatar.processing_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Sets the processing state on an avatar.
  """
  def set_processing_state(%Avatar{} = avatar, state) do
    avatar
    |> Ecto.Changeset.change(processing_state: state)
    |> Repo.update()
  end

  @doc """
  Uploads a file to the avatars S3 bucket at the given key.
  Returns `{:ok, location}` with the full object URL.
  """
  def upload_to_s3(file_path, key, opts \\ []) do
    bucket = S3Config.avatars_bucket_name()
    key = String.trim_leading(key, "/")

    upload_opts =
      [cache_control: "public, max-age=86400"]
      |> maybe_add_content_type(opts)

    result =
      file_path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket, key, upload_opts)
      |> ExAws.request!()

    location =
      case result[:body][:location] do
        "" -> S3Config.object_url(key, bucket)
        loc when is_binary(loc) and loc != "" -> loc
        _ -> S3Config.object_url(key, bucket)
      end

    {:ok, location}
  end

  defp maybe_add_content_type(opts, extra_opts) do
    case Keyword.get(extra_opts, :content_type) do
      nil -> opts
      ct -> Keyword.put(opts, :content_type, ct)
    end
  end

  @doc """
  Synchronizes an OAuth provider's profile image for a user.

  Downloads the image, uploads it to S3, creates an avatar record, and
  enqueues processing. Skips if the `source_url` matches the user's latest
  avatar from the same provider.
  """
  def sync_oauth_avatar(%User{} = _user, nil, _source), do: {:ok, :no_image}
  def sync_oauth_avatar(%User{} = _user, "", _source), do: {:ok, :no_image}

  def sync_oauth_avatar(%User{} = user, image_url, source)
      when source in [:google, :facebook] do
    latest =
      from(a in Avatar,
        where: a.user_id == ^user.id and a.source == ^source,
        order_by: [desc: a.inserted_at],
        limit: 1
      )
      |> Repo.one()

    if latest && latest.source_url == image_url &&
         latest.processing_state == :completed do
      {:ok, :unchanged}
    else
      download_and_create_avatar(user, image_url, source)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp download_and_create_avatar(user, image_url, source) do
    case Req.get(image_url, max_redirects: 5, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}}
      when is_binary(body) and byte_size(body) > 0 ->
        extension = detect_extension_from_url(image_url)
        avatar_id = Ecto.ULID.generate()
        key = "#{user.id}/#{avatar_id}/original#{extension}"

        tmp_path =
          Path.join(System.tmp_dir!(), "avatar_oauth_#{avatar_id}#{extension}")

        try do
          File.write!(tmp_path, body)

          {:ok, location} =
            upload_to_s3(tmp_path, key, content_type: mime_for_ext(extension))

          {:ok, avatar} =
            create_avatar(user, %{
              source: source,
              original_path: location,
              source_url: image_url
            })

          case Oban.insert(YscWeb.Workers.AvatarProcessor.new(%{id: avatar.id})) do
            {:ok, _job} ->
              {:ok, avatar}

            {:error, reason} ->
              Ysc.Logging.warning("Failed to enqueue avatar processing job",
                extra: %{avatar_id: avatar.id, reason: inspect(reason)}
              )

              {:error, reason}
          end
        after
          File.rm(tmp_path)
        end

      {:ok, %Req.Response{status: status}} ->
        Ysc.Logging.warning(
          "OAuth avatar download returned status #{status}",
          extra: %{user_id: user.id, source: source, url: image_url}
        )

        {:error, :download_failed}

      {:error, reason} ->
        Ysc.Logging.warning(
          "OAuth avatar download failed: #{inspect(reason)}",
          extra: %{user_id: user.id, source: source}
        )

        {:error, :download_failed}
    end
  end

  defp detect_extension_from_url(url) do
    path = URI.parse(url).path || ""
    ext = Path.extname(path) |> String.downcase()

    if ext in [".jpg", ".jpeg", ".png", ".webp", ".gif"] do
      ext
    else
      ".jpg"
    end
  end

  defp mime_for_ext(".jpg"), do: "image/jpeg"
  defp mime_for_ext(".jpeg"), do: "image/jpeg"
  defp mime_for_ext(".png"), do: "image/png"
  defp mime_for_ext(".webp"), do: "image/webp"
  defp mime_for_ext(".gif"), do: "image/gif"
  defp mime_for_ext(_), do: "image/jpeg"

  @doc """
  Returns the avatar URL to use for display.
  Prefers `profile_path` by default, falls back through sizes.
  """
  def avatar_url(avatar, size \\ :profile)

  def avatar_url(%Avatar{processing_state: :completed} = avatar, size) do
    case size do
      :thumb -> avatar.thumb_path || avatar.profile_path || avatar.large_path
      :profile -> avatar.profile_path || avatar.large_path || avatar.thumb_path
      :large -> avatar.large_path || avatar.profile_path || avatar.thumb_path
    end
  end

  def avatar_url(_, _), do: nil

  @doc """
  Resolves the avatar URL from a user struct that may have `current_avatar` preloaded.

  Safely checks whether the association is loaded and the avatar has completed
  processing before returning the URL.  Returns `nil` when no avatar is available.
  """
  def subscribe_avatar_updates(user_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, avatar_topic(user_id))
  end

  def broadcast_avatar_processed(user_id) do
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      avatar_topic(user_id),
      {:avatar_processed, user_id}
    )
  end

  defp avatar_topic(user_id), do: "avatars:user:#{user_id}"

  def resolve_user_avatar_url(user, size \\ :profile)

  def resolve_user_avatar_url(%User{} = user, size) do
    if Ecto.assoc_loaded?(user.current_avatar) do
      avatar_url(user.current_avatar, size)
    else
      nil
    end
  end

  def resolve_user_avatar_url(_user, _size), do: nil
end
