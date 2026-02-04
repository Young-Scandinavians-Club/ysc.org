defmodule YscWeb.TrixUploadsController do
  alias Ysc.Posts
  alias Ysc.Accounts.User
  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.Validators.FileValidator
  use YscWeb, :controller

  @temp_dir "/tmp/image_processor"

  # sobelow_skip ["XSS.SendResp"]
  def create(conn, %{"post_id" => post_id} = params) do
    current_user = conn.assigns[:current_user]
    updated_image = upload_file(params, current_user)

    post = Posts.get_post(post_id)

    if post != nil do
      set_cover_photo(post, updated_image.id, current_user)
    end

    send_resp(conn, 201, get_return_url(updated_image))
  end

  defp set_cover_photo(post, image_id, user) do
    if post.image_id == nil do
      Posts.update_post(post, %{"image_id" => image_id}, user)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp upload_file(
         %{"file" => %Plug.Upload{}} = plug_upload,
         %User{} = current_user
       ) do
    # 1. Upload raw file to s3
    # 2. Insert DB entry
    # 3. Run the image processor task and await the results
    # 4. Return optimized url or raw url

    tmp_path = plug_upload["file"].path

    # Validate file MIME type before processing
    case FileValidator.validate_image(tmp_path, [
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

    upload_result = Media.upload_file_to_s3(tmp_path)
    raw_s3_path = upload_result[:body][:location]

    # Defensive check: ensure location is not empty (should be handled by upload_file_to_s3, but double-check)
    raw_s3_path =
      if raw_s3_path == "" or is_nil(raw_s3_path) do
        # Fallback: construct URL from key if location is still empty
        key = upload_result[:body][:key] || Path.basename(tmp_path)
        S3Config.object_url(key)
      else
        raw_s3_path
      end

    {:ok, new_image} =
      Media.add_new_image(
        %{
          raw_image_path: URI.encode(raw_s3_path),
          user_id: current_user.id
        },
        current_user
      )

    File.mkdir_p!(@temp_dir)
    tmp_output_file = "#{@temp_dir}/#{new_image.id}"
    # Format will be determined dynamically in process_image_upload
    optimized_output_path = "#{tmp_output_file}_optimized"
    thumbnail_output_path = "#{tmp_output_file}_thumb"

    updated_image =
      Media.process_image_upload(
        new_image,
        tmp_path,
        thumbnail_output_path,
        optimized_output_path
      )

    # Clean up processed files with any extension
    ["_optimized", "_thumb"]
    |> Enum.each(fn suffix ->
      [".jpg", ".jpeg", ".png", ".webp"]
      |> Enum.each(fn ext ->
        path = "#{tmp_output_file}#{suffix}#{ext}"
        if File.exists?(path), do: File.rm(path)
      end)
    end)

    updated_image
  end

  defp get_return_url(%Media.Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp get_return_url(%Media.Image{optimized_image_path: optimized_path}),
    do: optimized_path
end
