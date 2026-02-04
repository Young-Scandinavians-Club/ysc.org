defmodule YscWeb.Components.ImageUploadComponent do
  @moduledoc """
  LiveView component for image upload functionality.

  Provides an interactive interface for uploading images with preview and progress tracking.
  """
  use YscWeb, :live_component

  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form id="upload-form" phx-submit="save-upload" phx-change="validate-upload">
        <label
          class="flex p-6 flex-col items-center justify-center w-full min-h-72 border-2 border-zinc-300 border-dashed rounded-lg cursor-pointer bg-zinc-50 hover:bg-zinc-100"
          phx-drop-target={@uploads.media_uploads.ref}
        >
          <.live_file_input upload={@uploads.media_uploads} class="hidden" />

          <div class="flex flex-row flex-wrap gap-2">
            <%= for entry <- @uploads.media_uploads.entries do %>
              <article class="upload-entry">
                <figure class="w-28 group relative">
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    aria-label="cancel"
                  >
                    <div class="hidden group-hover:block absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 text-red-500 z-10">
                      <.icon name="hero-x-circle" class="w-10 h-10" />
                    </div>
                    <.live_img_preview
                      entry={entry}
                      class="group-hover:blur"
                      width="120"
                      height="120"
                    />
                    <figcaption class="text-sm truncate overflow-hidden bg-zinc-100 text-zinc-600 w-28 z-8 absolute inset-x-0 bottom-0 py-1">
                      <%= entry.client_name %>
                    </figcaption>
                  </button>
                </figure>

                <%!-- Phoenix.Component.upload_errors/2 returns a list of error atoms --%>
                <%= for err <- upload_errors(@uploads.media_uploads, entry) do %>
                  <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
                    <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> <%= error_to_string(
                      err
                    ) %>
                  </p>
                <% end %>
              </article>
            <% end %>
          </div>

          <%!-- Phoenix.Component.upload_errors/1 returns a list of error atoms --%>
          <%= for err <- upload_errors(@uploads.media_uploads) do %>
            <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
              <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> <%= error_to_string(
                err
              ) %>
            </p>
          <% end %>

          <div
            :if={length(@uploads.media_uploads.entries) == 0}
            class="flex flex-col items-center justify-center pt-5 pb-6"
          >
            <.icon name="hero-cloud-arrow-up" class="w-8 h-10 mb-4 text-zinc-500" />
            <p class="mb-2 text-sm text-zinc-500">
              <span class="font-semibold">Click to upload</span> or drag and drop
            </p>
            <p class="text-xs text-zinc-500">
              SVG, PNG, JPG, JPEG or GIF
            </p>
          </div>
        </label>

        <div class="w-full flex justify-end pt-4">
          <.button
            type="submit"
            aria-disabled={length(@uploads.media_uploads.entries) == 0}
            disabled={length(@uploads.media_uploads.entries) == 0}
          >
            Upload
          </.button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uploaded_files, [])
     |> allow_upload(:media_uploads,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       external: &presign_upload/2,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate-upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media_uploads, ref)}
  end

  @impl true
  def handle_event("save-upload", _params, socket) do
    uploader = socket.assigns[:current_user]

    uploaded_files =
      consume_uploaded_entries(socket, :media_uploads, fn details, _entry ->
        raw_path = S3Config.object_url(details[:key])

        {:ok, new_image} =
          Media.add_new_image(
            %{
              raw_image_path: URI.encode(raw_path),
              user_id: uploader.id,
              upload_data: details
            },
            uploader
          )

        %{id: new_image.id}
        |> YscWeb.Workers.ImageProcessor.new()
        |> Oban.insert()

        {:ok, new_image}
      end)

    updated_socket =
      Enum.reduce(uploaded_files, socket, fn x, acc ->
        acc |> stream_insert(:images, x, at: 0)
      end)

    {:noreply,
     update(updated_socket, :uploaded_files, &(&1 ++ uploaded_files))
     |> push_navigate(to: ~p"/admin/media")}
  end

  defp presign_upload(entry, socket) do
    uploads = socket.assigns.uploads
    key = "public/#{entry.client_name}"

    config = %{
      region: S3Config.region(),
      access_key_id: S3Config.aws_access_key_id(),
      secret_access_key: S3Config.aws_secret_access_key()
    }

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(config, S3Config.bucket_name(),
        key: key,
        content_type: entry.client_type,
        max_file_size: uploads[entry.upload_config].max_file_size,
        expires_in: :timer.hours(1)
      )

    meta = %{
      uploader: "S3",
      key: key,
      url: S3Config.upload_url(),
      fields: fields
    }

    {:ok, meta, socket}
  end

  defp error_to_string(:too_large), do: "Too large"

  defp error_to_string(:not_accepted),
    do: "You have selected an unacceptable file type"

  defp error_to_string(:too_many_files), do: "You have selected too many files"
end
