defmodule YscWeb.Components.ImageUploadComponent do
  @moduledoc """
  LiveView component for image upload functionality.

  Provides an interactive interface for uploading images with preview and progress tracking.
  """
  use YscWeb, :live_component

  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.MediaLibraryUpload

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form id="upload-form" phx-submit="save-upload" phx-change="validate-upload">
        <label
          class={upload_dropzone_label_class()}
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
                      class="group-hover:blur h-[120px] w-[120px]"
                    />
                    <figcaption class="text-sm truncate overflow-hidden bg-zinc-100 text-zinc-600 w-28 z-8 absolute inset-x-0 bottom-0 py-1">
                      {entry.client_name}
                    </figcaption>
                  </button>
                </figure>

                <%= for err <- upload_errors(@uploads.media_uploads, entry) do %>
                  <.upload_error error={err} alert? />
                <% end %>
              </article>
            <% end %>
          </div>

          <%= for err <- upload_errors(@uploads.media_uploads) do %>
            <.upload_error error={err} alert? />
          <% end %>

          <div :if={length(@uploads.media_uploads.entries) == 0}>
            <.upload_dropzone_empty_state />
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
       external: &MediaLibraryUpload.presign/2,
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
end
