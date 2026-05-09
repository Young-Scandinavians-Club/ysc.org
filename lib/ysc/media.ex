defmodule Ysc.Media do
  @moduledoc """
  Context module for managing media files and images.

  Handles image upload, storage, processing, and retrieval operations.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Media
  alias Ysc.Media.ImageOps
  alias Ysc.S3Config
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.User

  @blur_hash_comp_x 4
  @blur_hash_comp_y 3
  @thumbnail_size 500
  @max_optimized_width 1920
  @max_optimized_height 1920
  @optimized_quality 85
  @topic "media"

  def subscribe_images do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @topic)
  end

  def broadcast_image_updated(%Media.Image{} = image) do
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      @topic,
      {__MODULE__, {:image_updated, image.id}}
    )
  end

  def list_images() do
    {:ok, Media.Image |> order_by(desc: :id) |> Repo.all()}
  end

  @doc """
  Gets all distinct years from images, ordered descending.
  """
  # sobelow_skip ["SQL.Query"]
  def get_available_years do
    # Use raw SQL to get distinct years efficiently
    # This avoids loading all timestamps and works around Ecto subquery limitations
    query = """
    SELECT DISTINCT EXTRACT(YEAR FROM inserted_at)::integer AS year
    FROM images
    ORDER BY year DESC
    """

    Repo.query!(query, [])
    |> Map.get(:rows)
    |> List.flatten()
  end

  @doc """
  Gets timeline indices (years with counts) for the scrubber.
  Returns a list of maps with :year and :count keys.
  """
  # sobelow_skip ["SQL.Query"]
  def get_timeline_indices do
    query = """
    SELECT
      EXTRACT(YEAR FROM inserted_at)::integer AS year,
      COUNT(id)::integer AS count
    FROM images
    GROUP BY EXTRACT(YEAR FROM inserted_at)
    ORDER BY year DESC
    """

    Repo.query!(query, [])
    |> Map.get(:rows)
    |> Enum.map(fn [year, count] -> %{year: year, count: count} end)
  end

  @doc """
  Total image count implied by `get_timeline_indices/0` rows (sum of per-year counts).

  Matches `count_images/0` when every row has a non-null `inserted_at`, which is true for
  normal `%Media.Image{}` records. Avoids a separate `COUNT(*)` round-trip when both the
  scrubber and the total are needed.
  """
  def total_image_count_from_timeline(timeline) when is_list(timeline) do
    Enum.reduce(timeline, 0, fn %{count: count}, acc ->
      acc + timeline_count_as_integer(count)
    end)
  end

  defp timeline_count_as_integer(n) when is_integer(n), do: n

  defp timeline_count_as_integer(%Decimal{} = d), do: Decimal.to_integer(d)

  defp timeline_count_as_integer(n) when is_binary(n) do
    {int, ""} = Integer.parse(n)
    int
  end

  @doc """
  Lists images with cursor-based pagination.
  Uses inserted_at and id as cursor for efficient pagination.

  Options:
  - :before_date - Only return images before this date
  - :start_at_year - Start from the beginning of this year
  - :limit - Number of images to return (default: 30)
  - :search - Case-insensitive fuzzy search on title, alt_text, and filename
  """
  def list_images_cursor(opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    before_date = Keyword.get(opts, :before_date)
    start_at_year = Keyword.get(opts, :start_at_year)
    search = Keyword.get(opts, :search)

    query =
      from i in Media.Image,
        order_by: [desc: i.inserted_at, desc: i.id],
        limit: ^limit

    query =
      cond do
        before_date ->
          from i in query,
            where: i.inserted_at < ^before_date

        start_at_year ->
          end_date =
            DateTime.new!(
              Date.new!(start_at_year, 12, 31),
              ~T[23:59:59],
              "Etc/UTC"
            )

          from i in query,
            where: i.inserted_at <= ^end_date

        true ->
          query
      end

    query =
      if search && search != "" do
        search_pattern = "%#{search}%"

        from i in query,
          where:
            ilike(i.title, ^search_pattern) or
              ilike(i.alt_text, ^search_pattern) or
              ilike(
                fragment(
                  "regexp_replace(?, '.*/([^/]+)$', '\\1')",
                  i.raw_image_path
                ),
                ^search_pattern
              )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists all images, optionally filtered by year, grouped by year.
  Returns a map with years as keys and lists of images as values.
  """
  def list_images_grouped_by_year(year \\ nil) do
    query =
      from i in Media.Image,
        order_by: [{:desc, :inserted_at}]

    query =
      if year do
        start_date =
          DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC")

        end_date =
          DateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59], "Etc/UTC")

        from i in query,
          where: i.inserted_at >= ^start_date and i.inserted_at <= ^end_date
      else
        query
      end

    images = Repo.all(query)

    Enum.group_by(images, fn image ->
      image.inserted_at.year
    end)
    |> Enum.sort_by(fn {year, _images} -> year end, :desc)
    |> Enum.into(%{})
  end

  @doc """
  Count the number of published events.
  """
  def count_images do
    Media.Image
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Lists all images that are in :unprocessed or :processing state.
  These are images that need to be processed or reprocessed.
  """
  def list_unprocessed_images do
    Repo.all(
      from i in Media.Image,
        where: i.processing_state in [:unprocessed, :processing],
        order_by: [asc: :inserted_at]
    )
  end

  @spec list_images_per_year() :: any()
  def list_images_per_year() do
    {:ok, images} = list_images()

    Enum.reduce(images, %{}, fn image, new_map ->
      year = image.inserted_at.year
      c = Map.get(new_map, year, [])
      Map.put(new_map, year, [image | c])
    end)
  end

  @spec fetch_image(any()) :: any()
  def fetch_image(id) do
    Repo.get(Media.Image, id)
  end

  @doc """
  Computes a SHA-256 content hash for the file at the given path.

  Reads the file in chunks to avoid loading large images into RAM. Returns a
  lowercase hex-encoded string, e.g. `"a3f2..."`.
  """
  # sobelow_skip ["Traversal.FileModule"]
  def compute_file_hash(path) do
    path
    |> File.stream!(2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Looks up an image by its content hash. Returns the `%Media.Image{}` struct if
  found, or `nil` if no image with that hash exists.
  """
  def find_image_by_content_hash(hash) when is_binary(hash) do
    Repo.get_by(Media.Image, content_hash: hash)
  end

  @doc """
  Copies all processed output fields from `source` onto `target` and marks the
  target as `"completed"`. Used to skip re-processing when the same raw image
  has already been processed before.
  """
  def reuse_existing_processed_image(
        %Media.Image{} = target,
        %Media.Image{} = source
      ) do
    attrs = %{
      optimized_image_path: source.optimized_image_path,
      thumbnail_path: source.thumbnail_path,
      blur_hash: source.blur_hash,
      width: source.width,
      height: source.height,
      processing_state: "completed"
    }

    update_processed_image(target, attrs)
  end

  @doc """
  Persists the content hash onto an existing image record.
  """
  def set_content_hash(%Media.Image{} = image, hash) when is_binary(hash) do
    image
    |> Media.Image.add_image_changeset(%{content_hash: hash})
    |> Repo.update()
  end

  def get_image!(id) do
    Repo.get!(Media.Image, id)
  end

  def add_new_image(attrs, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_create, current_user) do
      %Media.Image{user_id: current_user.id}
      |> Media.Image.add_image_changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_image(%Media.Image{} = image, attrs, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_update, current_user, image) do
      image
      |> Media.Image.edit_image_changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_image(%Media.Image{} = image, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_delete, current_user, image) do
      Repo.delete(image)
    end
  end

  def set_image_processing_state(%Media.Image{} = image, state) do
    image
    |> Media.Image.image_processing_state_changeset(state)
    |> Repo.update()
    |> case do
      {:ok, image} = result ->
        broadcast_image_updated(image)
        result

      error ->
        error
    end
  end

  def update_processed_image(%Media.Image{} = image, attrs) do
    changeset = Media.Image.processed_image_changeset(image, attrs)
    image = Repo.update!(changeset)
    broadcast_image_updated(image)
    image
  end

  def process_image_upload(
        %Media.Image{} = image,
        path,
        thumbnail_output_path,
        optimized_output_path
      ) do
    {:ok, parsed_image} = Image.open(path)
    {:ok, oriented_image} = autorotate_image(parsed_image)

    # Bake EXIF orientation into pixels before stripping metadata so WebP outputs
    # render the same way as the original camera image.
    {:ok, meta_free_image} =
      Image.remove_metadata(oriented_image, [:exif, :iptc, :xmp])

    # Store display dimensions after orientation has been normalized.
    original_width = Image.width(meta_free_image)
    original_height = Image.height(meta_free_image)

    # Detect original format from file extension
    original_format = detect_image_format(path)

    # Optimized and thumbnail outputs are always written as WebP
    output_format = determine_output_format(original_format)

    # Ensure optimized output path uses correct extension
    optimized_output_path =
      ensure_format_extension(optimized_output_path, output_format)

    thumbnail_output_path =
      ensure_format_extension(thumbnail_output_path, output_format)

    # Create optimized version: maintain aspect ratio, cap at max dimensions, preserve quality
    optimized_image =
      if original_width > @max_optimized_width or
           original_height > @max_optimized_height do
        # Resize if too large, maintaining aspect ratio
        scale =
          min(
            @max_optimized_width / original_width,
            @max_optimized_height / original_height
          )

        {:ok, resized} = Image.resize(meta_free_image, scale)
        resized
      else
        # Keep original size if within limits
        meta_free_image
      end

    # Write optimized image with quality settings
    write_options = get_write_options(output_format, @optimized_quality)

    _write_result =
      Image.write(optimized_image, optimized_output_path, write_options)

    # Create thumbnail (always 500px on longest side)
    {:ok, thumbnail_image} = Image.thumbnail(meta_free_image, @thumbnail_size)

    _thumbnail_write_result =
      Image.write(thumbnail_image, thumbnail_output_path, write_options)

    upload_result =
      upload_files_to_s3(
        thumbnail: thumbnail_output_path,
        optimized: optimized_output_path
      )

    # Downscale to very small and generate blurhash
    blur_hash =
      try do
        generate_blur_hash_safely(optimized_output_path, path)
      rescue
        _e ->
          # Return a default blurhash on failure
          "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      catch
        _kind, _reason ->
          # Return a default blurhash on failure
          "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      end

    # Use original dimensions for database (not resized dimensions)
    update_attrs = %{
      optimized_image_path: upload_result[:optimized],
      thumbnail_path: upload_result[:thumbnail],
      blur_hash: blur_hash,
      width: original_width,
      height: original_height,
      processing_state: "completed"
    }

    update_processed_image(image, update_attrs)
  end

  # Detect image format from file extension
  defp detect_image_format(path) do
    ext = Path.extname(path) |> String.downcase()

    case ext do
      ".jpg" -> :jpg
      ".jpeg" -> :jpeg
      ".png" -> :png
      ".webp" -> :webp
      # Default fallback
      _ -> :jpg
    end
  end

  # Always convert to WebP for optimal compression and modern browser support
  defp determine_output_format(_original_format), do: :webp

  defp autorotate_image(image) do
    ImageOps.autorotate(image)
  end

  # Ensure file path has correct extension for the format
  defp ensure_format_extension(path, format) do
    base_path = String.replace(path, ~r/\.[^.]+$/, "")
    extension = format_to_extension(format)
    "#{base_path}#{extension}"
  end

  # Catch-alls below are defensive; Dialyzer only sees `:webp` from `determine_output_format/1`.
  @dialyzer {:nowarn_function, format_to_extension: 1}
  @dialyzer {:nowarn_function, get_write_options: 2}

  # Convert format atom to file extension (outputs are always WebP; see `determine_output_format/1`)
  defp format_to_extension(:webp), do: ".webp"

  defp format_to_extension(other) do
    raise ArgumentError,
          "Ysc.Media.format_to_extension/1: unsupported format #{inspect(other)}"
  end

  # WebP uses effort level 6 (maximum compression, best size reduction)
  defp get_write_options(:webp, quality), do: [quality: quality, effort: 6]

  defp get_write_options(other, _quality) do
    raise ArgumentError,
          "Ysc.Media.get_write_options/2: unsupported format #{inspect(other)}"
  end

  def upload_file_to_s3(path),
    do: upload_file_to_s3(path, Path.basename(path), [])

  @doc """
  Uploads a file to S3 at the given key (e.g. to overwrite an existing object).
  Use this to replace the raw upload with a metadata-stripped version.

  ## Options
  - `:content_type` - The MIME type to set on the S3 object (e.g. `"application/pdf"`).
    When omitted, S3 infers the content type from the file extension.
  """
  def upload_file_to_s3(path, key) when is_binary(key),
    do: upload_file_to_s3(path, key, [])

  def upload_file_to_s3(path, key, opts)
      when is_binary(key) and is_list(opts) do
    bucket_name = S3Config.bucket_name()
    key = String.trim_leading(key, "/")

    upload_opts =
      [cache_control: "public, max-age=86400"]
      |> maybe_add_content_type(opts)

    result =
      path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket_name, key, upload_opts)
      |> ExAws.request!()

    # Always derive the public URL from `S3Config` (custom domain when set). ExAws
    # / Tigris may return a `location` on the default host, which must not be
    # stored when `S3_MEDIA_PUBLIC_BASE_URL` is configured.
    result_key = result[:body][:key] || key
    location = S3Config.object_url(result_key)

    # Return result with location in body for compatibility
    put_in(result, [:body, :location], location)
  end

  defp maybe_add_content_type(opts, extra_opts) do
    case Keyword.get(extra_opts, :content_type) do
      nil -> opts
      ct -> Keyword.put(opts, :content_type, ct)
    end
  end

  defp upload_files_to_s3(files) do
    Enum.map(files, fn {k, v} ->
      content_type = content_type_from_path(v)

      upload_response =
        upload_file_to_s3(v, Path.basename(v), content_type: content_type)

      location = upload_response[:body][:location]
      {k, location}
    end)
    |> Enum.into(%{})
  end

  defp content_type_from_path(path) do
    case path |> Path.extname() |> String.downcase() do
      ".webp" -> "image/webp"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      _ -> "application/octet-stream"
    end
  end

  # Generate blurhash safely, ensuring we don't create files in source directories
  # sobelow_skip ["Traversal.FileModule"]
  defp generate_blur_hash_safely(temp_image_path, original_path) do
    # Use the temp image file (optimized_output_path) which is already in /tmp
    # This ensures Blurhash won't create files in the seed directory

    # Generate blurhash from the temp file
    result =
      Blurhash.downscale_and_encode(
        temp_image_path,
        @blur_hash_comp_x,
        @blur_hash_comp_y
      )

    blur_hash =
      case result do
        {:ok, hash} ->
          hash

        {:error, reason} ->
          raise "Blurhash generation failed: #{inspect(reason)}"
      end

    # Clean up any PNG file that Blurhash might have created in the original directory
    # (Blurhash.downscale_and_encode may create a temporary PNG file in the source directory)
    original_dir = Path.dirname(original_path)
    original_base = Path.basename(original_path, Path.extname(original_path))
    potential_png = Path.join(original_dir, "#{original_base}.png")

    # Only clean up if the PNG exists and is in a seed/assets directory (to be safe)
    if File.exists?(potential_png) and
         String.contains?(original_path, "seed/assets") do
      try do
        File.rm(potential_png)
      rescue
        _ -> :ok
      end
    end

    blur_hash
  end
end
