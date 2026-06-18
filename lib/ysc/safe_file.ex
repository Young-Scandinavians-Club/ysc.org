defmodule Ysc.SafeFile do
  @moduledoc """
  Filesystem helpers that constrain paths to an expected root using `Path.safe_relative/2`.
  """

  @event_photo_tmp_prefix "event-photo-"
  @dev_event_photos_dir "tmp/dev_event_photos"

  @doc "Expanded system tmp directory used for event photo upload staging files."
  @spec event_photo_tmp_root() :: String.t()
  def event_photo_tmp_root, do: Path.expand(System.tmp_dir!())

  @doc "Expanded directory used by the Google Photos dev stub."
  @spec dev_event_photos_root() :: String.t()
  def dev_event_photos_root, do: Path.expand(@dev_event_photos_dir)

  @doc """
  Builds an absolute temp path for a staged event photo/video upload.

  Returns `{:ok, path}` or `:error` when identifiers or extensions are invalid.
  """
  @spec event_photo_tmp_path(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | :error
  def event_photo_tmp_path(collection_id, entry_uuid, client_name)
      when is_binary(collection_id) and is_binary(entry_uuid) and
             is_binary(client_name) do
    ext = Path.extname(client_name) |> String.downcase()

    with :ok <- validate_id_segment(collection_id),
         :ok <- validate_uuid_segment(entry_uuid),
         :ok <- validate_extension(ext) do
      filename =
        "#{@event_photo_tmp_prefix}#{collection_id}-#{entry_uuid}#{ext}"

      join_under_root(event_photo_tmp_root(), [filename])
    end
  end

  @doc """
  Returns `{:ok, absolute_path}` when `path` resolves under `root`, otherwise `:error`.
  """
  @spec resolve_under_root(String.t(), String.t()) :: {:ok, String.t()} | :error
  def resolve_under_root(root, path) when is_binary(root) and is_binary(path) do
    expanded_root = Path.expand(root)
    expanded_path = Path.expand(path)
    relative = Path.relative_to(expanded_path, expanded_root)

    cond do
      relative == "" ->
        :error

      String.starts_with?(relative, "/") or String.contains?(relative, "..") ->
        :error

      Path.expand(Path.join(expanded_root, relative)) == expanded_path ->
        {:ok, expanded_path}

      true ->
        :error
    end
  end

  @doc "Stats a file when its path resolves under `root`."
  @spec stat_under_root(String.t(), String.t()) ::
          {:ok, File.Stat.t()} | {:error, term()}
  def stat_under_root(root, path) when is_binary(root) and is_binary(path) do
    case resolve_under_root(root, path) do
      {:ok, absolute} -> File.stat(absolute)
      :error -> {:error, :invalid_path}
    end
  end

  @doc "Reads a file when its path resolves under `root`."
  @spec read_under_root(String.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def read_under_root(root, path) when is_binary(root) and is_binary(path) do
    with {:ok, absolute} <- resolve_under_root(root, path),
         {:ok, bytes} <- do_read(absolute) do
      {:ok, bytes}
    else
      :error -> {:error, :invalid_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes bytes to a basename file under `root`.

  Returns `{:ok, absolute_path}` or `{:error, :invalid_path}` when `filename` is
  not a safe basename or resolves outside `root`.
  """
  @spec write_under_root(String.t(), String.t(), binary()) ::
          {:ok, String.t()} | {:error, :invalid_path | term()}
  def write_under_root(root, filename, bytes)
      when is_binary(root) and is_binary(filename) and is_binary(bytes) do
    with :ok <- validate_basename(filename),
         {:ok, path} <- join_under_root(Path.expand(root), [filename]),
         :ok <- ensure_parent_dir(path),
         :ok <- do_write(path, bytes) do
      {:ok, path}
    else
      :error -> {:error, :invalid_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Copies a regular file to an absolute destination path (parent dirs created)."
  @spec copy_upload_to(String.t(), String.t()) :: :ok | {:error, term()}
  def copy_upload_to(src, dest) when is_binary(src) and is_binary(dest) do
    if File.regular?(src) do
      with :ok <- do_mkdir_p(Path.dirname(dest)) do
        do_copy!(src, dest)
        :ok
      end
    else
      {:error, :invalid_source}
    end
  end

  @doc """
  Copies a LiveView upload temp file into `dest` when `dest` is under `root`.

  The upload `src` is provided by Phoenix and is only copied after `dest` is validated.
  """
  @spec copy_upload_to(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_path | :invalid_source}
  def copy_upload_to(src, root, dest)
      when is_binary(src) and is_binary(root) and is_binary(dest) do
    with {:ok, absolute_dest} <- resolve_under_root(root, dest),
         true <- File.regular?(src) do
      do_copy!(src, absolute_dest)
      {:ok, absolute_dest}
    else
      :error -> {:error, :invalid_path}
      false -> {:error, :invalid_source}
    end
  end

  @doc "Removes a file when its path resolves under `root` (no-op when invalid)."
  @spec rm_under_root(String.t(), String.t()) :: :ok
  def rm_under_root(root, path) when is_binary(root) and is_binary(path) do
    case resolve_under_root(root, path) do
      {:ok, absolute} -> do_rm(absolute)
      :error -> :ok
    end
  end

  @doc """
  Resolves a dev-stub storage path for an event media file.

  Returns `{:ok, absolute_path}` or `:error`.
  """
  @spec dev_event_photo_path(String.t(), String.t()) ::
          {:ok, String.t()} | :error
  def dev_event_photo_path(event_id, filename)
      when is_binary(event_id) and is_binary(filename) do
    with :ok <- validate_id_segment(event_id),
         :ok <- validate_basename(filename),
         {:ok, absolute} <-
           join_under_root(dev_event_photos_root(), [event_id, filename]) do
      {:ok, absolute}
    else
      _ -> :error
    end
  end

  @doc "Creates parent directories and writes bytes for a path under `dev_event_photos_root/0`."
  @spec write_dev_event_photo(String.t(), String.t(), binary()) ::
          :ok | {:error, term()}
  def write_dev_event_photo(event_id, filename, bytes)
      when is_binary(event_id) and is_binary(filename) and is_binary(bytes) do
    with {:ok, path} <- dev_event_photo_path(event_id, filename),
         :ok <- do_mkdir_p(Path.dirname(path)),
         :ok <- do_write(path, bytes) do
      :ok
    else
      :error -> {:error, :invalid_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp join_under_root(root, segments) when is_list(segments) do
    case validate_path_segments(segments) do
      :ok ->
        relative = Path.join(segments)
        resolve_under_root(root, Path.join(Path.expand(root), relative))

      :error ->
        :error
    end
  end

  defp validate_path_segments(segments) do
    if Enum.all?(segments, &valid_path_segment?/1), do: :ok, else: :error
  end

  defp valid_path_segment?(segment) do
    segment != "" and segment == Path.basename(segment) and
      not String.contains?(segment, ["..", "/", "\\"])
  end

  defp validate_basename(filename) do
    if filename == Path.basename(filename) and valid_path_segment?(filename),
      do: :ok,
      else: :error
  end

  defp validate_id_segment(id) do
    if String.match?(id, ~r/^[A-Za-z0-9_-]+$/) and valid_path_segment?(id),
      do: :ok,
      else: :error
  end

  defp validate_uuid_segment(uuid) do
    if String.match?(uuid, ~r/^[0-9a-f-]+$/i) and valid_path_segment?(uuid),
      do: :ok,
      else: :error
  end

  defp validate_extension(ext) do
    cond do
      ext == "" -> :ok
      String.match?(ext, ~r/^\.[a-z0-9]+$/) -> :ok
      true -> :error
    end
  end

  defp ensure_parent_dir(path), do: do_mkdir_p(Path.dirname(path))

  # Paths are validated with Path.safe_relative/2 before File operations run.
  # sobelow_skip ["Traversal.FileModule"]
  defp do_read(path), do: File.read(path)

  # sobelow_skip ["Traversal.FileModule"]
  defp do_copy!(src, dest), do: File.cp!(src, dest)

  # sobelow_skip ["Traversal.FileModule"]
  defp do_rm(path), do: File.rm(path)

  # sobelow_skip ["Traversal.FileModule"]
  defp do_mkdir_p(dir), do: File.mkdir_p(dir)

  # sobelow_skip ["Traversal.FileModule"]
  defp do_write(path, bytes), do: File.write(path, bytes)
end
