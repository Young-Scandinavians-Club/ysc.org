defmodule YscWeb.TrixUploadsController do
  alias Ysc.Posts
  alias Ysc.Media
  alias YscWeb.Validators.FileValidator
  use YscWeb, :controller

  @temp_dir "/tmp/image_processor"
  @max_file_size 25 * 1024 * 1024

  def create(
        conn,
        %{"file" => %Plug.Upload{path: path, filename: filename} = upload} =
          params
      ) do
    current_user = conn.assigns[:current_user]

    case check_file_size(path) do
      :ok ->
        if FileValidator.image?(path) do
          handle_image_upload(conn, upload, params, current_user)
        else
          handle_file_upload(conn, path, filename)
        end

      {:error, :too_large} ->
        conn
        |> put_status(413)
        |> json(%{error: "File too large. Maximum size is 25 MB."})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "No file provided"})
  end

  # --- Image path (media library) ---

  defp handle_image_upload(
         conn,
         %Plug.Upload{filename: filename} = upload,
         params,
         current_user
       ) do
    case upload_image_file(upload, current_user) do
      {:ok, updated_image} ->
        if post_id = params["post_id"] do
          post = Posts.get_post(post_id)

          if post != nil,
            do: set_cover_photo(post, updated_image.id, current_user)
        end

        url = get_image_url(updated_image)

        conn
        |> put_status(201)
        |> json(%{url: url, filename: filename, content_type: "image"})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: reason})
    end
  end

  defp set_cover_photo(post, image_id, user) do
    if post.image_id == nil do
      Posts.update_post(post, %{"image_id" => image_id}, user)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp upload_image_file(%Plug.Upload{path: path} = _upload, current_user) do
    case FileValidator.validate_image(path, [
           ".jpg",
           ".jpeg",
           ".png",
           ".gif",
           ".webp"
         ]) do
      {:ok, _mime_type} ->
        upload_result = Media.upload_file_to_s3(path)

        {:ok, new_image} =
          Media.add_new_image(
            %{
              raw_image_path: upload_result[:body][:location],
              user_id: current_user.id
            },
            current_user
          )

        File.mkdir_p!(@temp_dir)
        tmp_output_file = "#{@temp_dir}/#{new_image.id}"
        optimized_output_path = "#{tmp_output_file}_optimized"
        thumbnail_output_path = "#{tmp_output_file}_thumb"

        updated_image =
          Media.process_image_upload(
            new_image,
            path,
            thumbnail_output_path,
            optimized_output_path
          )

        ["_optimized", "_thumb"]
        |> Enum.each(fn suffix ->
          [".jpg", ".jpeg", ".png", ".webp"]
          |> Enum.each(fn ext ->
            file_path = "#{tmp_output_file}#{suffix}#{ext}"
            if File.exists?(file_path), do: File.rm(file_path)
          end)
        end)

        {:ok, updated_image}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_image_url(%Media.Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp get_image_url(%Media.Image{optimized_image_path: path}), do: path

  # --- Non-image path (raw S3 upload, no media library) ---

  defp handle_file_upload(conn, path, filename) do
    case FileValidator.validate_attachment(path, filename) do
      {:ok, mime} ->
        upload_result =
          Media.upload_file_to_s3(path, filename, content_type: mime)

        conn
        |> put_status(201)
        |> json(%{
          url: upload_result[:body][:location],
          filename: filename,
          content_type: mime
        })

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: reason})
    end
  end

  # --- Shared helpers ---

  defp check_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_file_size -> {:error, :too_large}
      _ -> :ok
    end
  end
end
