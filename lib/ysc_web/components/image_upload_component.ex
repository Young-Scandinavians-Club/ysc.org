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
                <.upload_entry_preview
                  entry={entry}
                  cancel="cancel-upload"
                  preview_class="group-hover:blur-sm h-[120px] w-[120px]"
                  figure_class="w-28 group relative"
                />

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
