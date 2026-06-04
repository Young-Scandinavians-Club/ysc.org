defmodule YscWeb.Uploads do
  @moduledoc """
  Conveniences for working with uploads.
  """
  use Phoenix.Component
  alias Phoenix.LiveView

  alias Ysc.Media
  alias YscWeb.Validators.FileValidator

  embed_templates("uploads/*")

  @temp_dir "/tmp/image_processor"

  attr :paths, :list, required: true, doc: "A list of URI paths"
  def figure_group(assigns)

  attr :src, :string, required: true, doc: "The absolute URI path to the image"
  attr :caption, :string, default: ""
  slot :inner_block
  def figure(assigns)

  attr :entry, Phoenix.LiveView.UploadEntry, required: true
  def progress(assigns)

  @doc """
  Returns the directory where uploads are stored.
  """
  def uploads_dir do
    Application.app_dir(:ysc, ["priv", "static", "uploads"])
  end

  @doc """
  Consumes the given upload entries and copies them to the uploads directory.
  """
  def consume_entries(%LiveView.Socket{} = socket, name)
      when is_atom(name) or is_binary(name) do
    user_id = socket.assigns.user_id
    current_user = Ysc.Accounts.get_user!(user_id)

    LiveView.consume_uploaded_entries(socket, name, fn a, b ->
      consume_entry(a, b, current_user)
    end)
  end

  @doc """
  Consumes the uploaded entries for the given `name` and adds them to the end
  of the list at the given `key` in assigns.
  """
  def consume_append_entries(socket, name, key) do
    consume_and_update(socket, name, key, &(&2 ++ &1))
  end

  @doc """
  Consumes the uploaded entries for the given `name` and adds them to the front
  of the list at the given `key` in assigns.
  """
  def consume_prepend_entries(socket, name, key) do
    consume_and_update(socket, name, key, &(&1 ++ &2))
  end

  @doc """
  Consumes the uploaded entries for the given `name` and replaces the given `key`
  in assigns with the new entries.

  This function respects the `:max_entries` option of the LiveView UploadConfig and
  will update the assigns with the first item in the list when the config has
  `max_entries: 1`.
  """
  def consume_replace_entries(socket, name, key) do
    case socket.assigns.uploads do
      %{^name => %Phoenix.LiveView.UploadConfig{max_entries: 1}} ->
        consume_and_update(socket, name, key, fn [x | _], _ -> x end)

      %{^name => %Phoenix.LiveView.UploadConfig{}} ->
        consume_and_update(socket, name, key, fn entries, _ -> entries end)

      _ ->
        raise "no upload named #{name} found"
    end
  end

  @doc """
  Consumes the uploaded entries for the given `name` and supplies them to an update
  callback for the given `key` in assigns.
  """
  def consume_and_update(%LiveView.Socket{} = socket, name, key, update)
      when (is_atom(name) or is_binary(name)) and is_atom(key) and
             (is_function(update, 2) or is_function(update, 3)) do
    paths = consume_entries(socket, name)
    update_after_consume(socket, key, paths, update)
  end

  @doc """
  Consumes a single upload entry.

  This is useful mostly for consuming auto-uploaded entries.
  """
  def consume_on_done(
        %LiveView.Socket{} = socket,
        %LiveView.UploadEntry{} = entry
      ) do
    current_user = socket.assigns.current_user

    if entry.done? do
      LiveView.consume_uploaded_entry(socket, entry, fn meta ->
        consume_entry(meta, entry, current_user)
      end)
    end
  end

  @doc """
  Consume the entry and updates the socket via the given `update callback.
  """
  def update_on_done(
        %LiveView.Socket{} = socket,
        %LiveView.UploadEntry{} = entry,
        key,
        update \\ &[&1 | &2]
      )
      when is_atom(key) and (is_function(update, 2) or is_function(update, 3)) do
    if path = consume_on_done(socket, entry) do
      update_after_consume(socket, key, path, update)
    else
      socket
    end
  end

  defp update_after_consume(socket, key, path, update)
       when is_function(update, 2) do
    Phoenix.Component.update(socket, key, &update.(path, &1))
  end

  defp update_after_consume(socket, key, path, update)
       when is_function(update, 3) do
    Phoenix.Component.update(socket, key, &update.(path, &1, &2))
  end

  @doc false
  def consume_entry(%{path: path} = _details, _params, current_user) do
    # Validate file MIME type before processing
    case FileValidator.validate_image(path, [
           ".jpg",
           ".jpeg",
           ".png",
           ".gif",
           ".webp"
         ]) do
      {:ok, _mime_type} ->
        :ok

      {:error, reason} ->
        raise "File validation failed: #{reason}"
    end

    hash = Media.compute_file_hash(path)

    case Media.find_image_by_content_hash(hash) do
      %Media.Image{processing_state: :failed} ->
        consume_insert_new_image_after_hash(path, hash, current_user)

      %Media.Image{} = existing ->
        {:ok, existing.id}

      nil ->
        consume_insert_new_image_after_hash(path, hash, current_user)
    end
  end

  def consume_entry(%{uploader: _} = meta, _entry, _current_user) do
    # External upload
    {:ok, meta}
  end

  defp consume_insert_new_image_after_hash(path, hash, current_user) do
    upload_result = Media.upload_file_to_s3(path)

    case Media.add_new_image(
           %{
             raw_image_path: upload_result[:body][:location],
             content_hash: hash
           },
           current_user
         ) do
      {:ok, new_image} ->
        make_temp_dir(@temp_dir)
        tmp_output_file = "#{@temp_dir}/#{new_image.id}"
        optimized_output_path = "#{tmp_output_file}_optimized.png"
        thumbnail_output_path = "#{tmp_output_file}_thumb.png"

        updated_image =
          Media.process_image_upload(
            new_image,
            path,
            thumbnail_output_path,
            optimized_output_path
          )

        {:ok, updated_image.id}

      {:error, _changeset} ->
        case Media.find_image_by_content_hash(hash) do
          %Media.Image{processing_state: :failed} ->
            raise "Could not save image."

          %Media.Image{} = existing ->
            {:ok, existing.id}

          nil ->
            raise "Could not save image."
        end
    end
  end

  @doc """
  Returns the static path to the given `file`.
  """
  def upload_path(file) do
    YscWeb.Router.Helpers.static_path(YscWeb.Endpoint, "/uploads/#{file}")
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp make_temp_dir(path) do
    File.mkdir(path)
  end
end
