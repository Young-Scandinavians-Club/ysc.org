defmodule Ysc.Merch.ImageImport do
  @moduledoc """
  Copies a Printful-hosted product image into our own media library.

  The shop renders images from the internal `images` table (blur hash,
  optimized and thumbnail sizes, our CDN), never from Printful URLs. This
  mirrors the normal upload path: store the original in S3, insert an
  `Ysc.Media.Image`, and let `YscWeb.Workers.ImageProcessor` generate the
  optimized variants.
  """
  require Ysc.Logging

  alias Ysc.Accounts.User
  alias Ysc.Http.UrlFetchGuard
  alias Ysc.Media
  alias Ysc.S3Config

  @max_bytes 15 * 1024 * 1024
  @extensions ~w(.jpg .jpeg .png .webp .gif)

  @type error ::
          :download_failed
          | :too_large
          | :empty
          | :blocked_url
          | :upload_failed
          | Ecto.Changeset.t()
          | term()

  @doc """
  Imports `url` as an image owned by `uploader`.

  Returns `{:ok, %Ysc.Media.Image{}}`. The image is usable immediately via its
  raw path; optimized sizes appear once the processor job completes.
  """
  @spec import(String.t(), String.t(), struct()) ::
          {:ok, struct()} | {:error, error()}
  def import(url, title, %User{} = uploader)
      when is_binary(url) and is_binary(title) do
    with {:ok, body, content_type} <- download(url) do
      store(url, title, body, content_type, uploader)
    end
  end

  defp download(url) do
    req_opts =
      [receive_timeout: 20_000, max_redirects: 0, decode_body: false]
      |> Keyword.merge(Application.get_env(:ysc, :merch_image_req_options, []))

    with :ok <- validate_url(url),
         {:ok, %Req.Response{status: 200, body: body} = response} <-
           Req.get(url, req_opts),
         :ok <- validate_body(body) do
      {:ok, body, content_type(response)}
    else
      {:error, reason} when reason in [:too_large, :empty, :blocked_url] ->
        {:error, reason}

      {:ok, %Req.Response{status: status}} ->
        Ysc.Logging.warning("Merch image download returned an error status",
          url: url,
          status: status
        )

        {:error, :download_failed}

      {:error, reason} ->
        Ysc.Logging.warning("Merch image download failed",
          url: url,
          error: inspect(reason)
        )

        {:error, :download_failed}
    end
  end

  defp validate_url(url) do
    case UrlFetchGuard.validate_url_for_server_fetch(url) do
      :ok -> :ok
      {:error, _reason} -> {:error, :blocked_url}
    end
  end

  defp validate_body(body) when is_binary(body) and byte_size(body) == 0,
    do: {:error, :empty}

  defp validate_body(body)
       when is_binary(body) and byte_size(body) > @max_bytes,
       do: {:error, :too_large}

  defp validate_body(body) when is_binary(body), do: :ok
  defp validate_body(_), do: {:error, :download_failed}

  defp content_type(%Req.Response{} = response) do
    case Req.Response.get_header(response, "content-type") do
      [value | _] -> value |> String.split(";") |> hd() |> String.trim()
      _ -> nil
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp store(url, title, body, content_type, uploader) do
    extension = extension(url, content_type)
    key = "merch/#{Ecto.ULID.generate()}/image#{extension}"

    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "merch_import_#{Ecto.ULID.generate()}#{extension}"
      )

    try do
      File.write!(tmp_path, body)

      Media.upload_file_to_s3(tmp_path, key,
        content_type:
          Media.image_content_type_from_filename("image#{extension}")
      )
    rescue
      error ->
        Ysc.Logging.warning("Merch image upload failed",
          url: url,
          error: Exception.message(error)
        )

        {:error, :upload_failed}
    else
      _upload_response ->
        create_image(key, title, uploader)
    after
      File.rm(tmp_path)
    end
  end

  defp create_image(key, title, uploader) do
    attrs = %{
      title: title,
      alt_text: title,
      raw_image_path: URI.encode(S3Config.object_url(key)),
      upload_data: %{"key" => key}
    }

    with {:ok, image} <- Media.add_new_image(attrs, uploader) do
      case %{id: image.id}
           |> YscWeb.Workers.ImageProcessor.new()
           |> Oban.insert() do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          # The raw image still displays; a media-library reprocess can finish it.
          Ysc.Logging.warning("Could not enqueue merch image processing",
            image_id: image.id,
            error: inspect(reason)
          )
      end

      {:ok, image}
    end
  end

  defp extension(url, content_type) do
    from_url =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> Kernel.||("")
      |> Path.extname()
      |> String.downcase()

    cond do
      from_url in @extensions -> from_url
      content_type == "image/png" -> ".png"
      content_type == "image/webp" -> ".webp"
      content_type == "image/gif" -> ".gif"
      true -> ".jpg"
    end
  end
end
