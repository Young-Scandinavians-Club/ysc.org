defmodule YscWeb.MediaPickerComponent do
  @moduledoc """
  A self-contained LiveComponent for selecting or uploading cover images.

  Provides three states:
  - Empty: shows an upload zone + "Choose from library" button
  - Filled: shows the selected image + "Clear" and "Change" buttons
  - Modal open: shows a searchable/filterable media library grid

  ## Usage

      <.live_component
        module={YscWeb.MediaPickerComponent}
        id={:cover_image}
        user_id={@current_user.id}
        image_id={@image_id}
      />

  Pass `multiple` (and optionally `max_entries`) to let the drop zone take
  several files at once. The library browser still picks one image at a time.

  The component sends messages to the parent LiveView:
  - `{YscWeb.MediaPickerComponent, id, image_id}` when an image is selected/uploaded
  - `{YscWeb.MediaPickerComponent, id, [image_id, ...]}` when several images are
    uploaded at once (only with `multiple`)
  - `{YscWeb.MediaPickerComponent, id, :cleared}` when the image is cleared
  """
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Ysc.Media
  alias YscWeb.MediaGalleryCursor

  @per_page 30
  @default_max_entries 20

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_modal?, false)
     |> assign(:search, "")
     |> assign(:selected_year, nil)
     |> assign(:available_years, [])
     |> assign(:end_of_timeline?, false)
     |> assign(:last_image_date, nil)
     |> assign(:last_image_id, nil)
     |> assign(:upload_configured?, false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:multiple, fn -> false end)
     |> assign_new(:max_entries, fn -> @default_max_entries end)
     |> configure_upload()}
  end

  # `multiple` and `max_entries` arrive as assigns, so the upload is configured
  # on the first update rather than in mount/1, and only once.
  defp configure_upload(%{assigns: %{upload_configured?: true}} = socket),
    do: socket

  defp configure_upload(socket) do
    max_entries =
      if socket.assigns.multiple, do: socket.assigns.max_entries, else: 1

    socket
    |> allow_upload(:media_picker_file,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: max_entries,
      auto_upload: true
    )
    |> assign(:upload_configured?, true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"media-picker-#{@id}"} class="not-prose">
      <%= if has_image?(@image_id) do %>
        <div class="relative group">
          <div class="absolute inset-0 flex items-center justify-center gap-2 opacity-0 group-hover:opacity-100 transition bg-black/30 rounded-lg z-10">
            <button
              type="button"
              phx-click="clear-image"
              phx-target={@myself}
              class="flex items-center justify-center w-10 h-10 rounded-full bg-white/90 hover:bg-white shadow-md"
              aria-label="Remove image"
            >
              <.icon name="hero-x-mark" class="w-5 h-5 text-red-600" />
            </button>
            <button
              type="button"
              phx-click="open-picker"
              phx-target={@myself}
              class="flex items-center justify-center w-10 h-10 rounded-full bg-white/90 hover:bg-white shadow-md"
              aria-label="Change image"
            >
              <.icon name="hero-arrows-right-left" class="w-5 h-5 text-zinc-700" />
            </button>
          </div>
          <.live_component
            module={YscWeb.Components.Image}
            id={"media-picker-preview-#{@id}"}
            image_id={@image_id}
            preferred_type={:optimized}
          />
        </div>
      <% else %>
        <div class="space-y-3">
          <form
            id={"#{@id}-upload-form"}
            class="upload-component"
            action="#"
            phx-change="validate-upload"
            phx-drop-target={@uploads.media_picker_file.ref}
            phx-submit="save-upload"
            phx-target={@myself}
          >
            <label
              phx-drop-target={@uploads.media_picker_file.ref}
              class={upload_dropzone_label_class(min_height: "min-h-52")}
            >
              <.live_file_input upload={@uploads.media_picker_file} class="hidden" />

              <div class="flex flex-row flex-wrap gap-2">
                <%= for entry <- @uploads.media_picker_file.entries do %>
                  <article class="upload-entry">
                    <figure class="group relative">
                      <button
                        type="button"
                        aria-label="cancel"
                        phx-click="cancel-upload"
                        phx-target={@myself}
                        phx-value-ref={entry.ref}
                        class="upload-entry__cancel w-full"
                      >
                        <div class="hidden group-hover:block absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 text-red-500 z-10">
                          <.icon name="hero-x-circle" class="w-10 h-10" />
                        </div>
                        <.live_img_preview
                          entry={entry}
                          class={[
                            "group-hover:blur-sm rounded-lg",
                            if(@multiple,
                              do: "size-28 object-cover",
                              else: "h-60 w-full"
                            )
                          ]}
                        />
                      </button>
                    </figure>

                    <%= for err <- upload_errors(@uploads.media_picker_file, entry) do %>
                      <.upload_error error={err} />
                    <% end %>
                  </article>
                <% end %>
              </div>

              <%= for err <- upload_errors(@uploads.media_picker_file) do %>
                <.upload_error error={err} />
              <% end %>

              <div :if={length(@uploads.media_picker_file.entries) == 0}>
                <.upload_dropzone_empty_state
                  size={:compact}
                  formats={
                    if @multiple,
                      do: "PNG, JPG, JPEG, GIF or WebP · select several at once",
                      else: "PNG, JPG, JPEG, GIF or WebP"
                  }
                />
              </div>
            </label>

            <div
              :if={length(@uploads.media_picker_file.entries) > 0}
              class="flex justify-end mt-3"
            >
              <.button type="submit" phx-disable-with="Uploading...">
                {upload_button_label(length(@uploads.media_picker_file.entries))}
              </.button>
            </div>
          </form>

          <button
            type="button"
            phx-click="open-picker"
            phx-target={@myself}
            class="w-full flex items-center justify-center gap-2 text-sm font-medium text-zinc-600 hover:text-zinc-900 border border-zinc-200 rounded-lg py-2 px-3 hover:bg-zinc-50 transition"
          >
            <.icon name="hero-photo" class="w-4 h-4" /> Choose from library
          </button>
        </div>
      <% end %>

      <.modal
        :if={@show_modal?}
        id={"media-picker-modal-#{@id}"}
        show
        on_cancel={JS.push("close-picker", target: @myself)}
        max_width="max-w-5xl"
      >
        <div class="space-y-4">
          <h2 class="text-lg text-zinc-800 type-subhead">
            Media library
          </h2>

          <.admin_media_library_browser
            id={@id}
            grid_id={"media-picker-grid-#{@id}"}
            target={@myself}
            search={@search}
            selected_year={@selected_year}
            available_years={@available_years}
            picker_images={@streams.picker_images}
            end_of_timeline?={@end_of_timeline?}
          />
        </div>
      </.modal>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("validate-upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media_picker_file, ref)}
  end

  @impl true
  def handle_event("save-upload", _params, socket) do
    %{id: id, multiple: multiple?} = socket.assigns

    case {YscWeb.Uploads.consume_entries(socket, :media_picker_file), multiple?} do
      {[], _} ->
        {:noreply, socket}

      {image_ids, true} ->
        send(self(), {__MODULE__, id, image_ids})
        {:noreply, socket}

      {[image_id], false} ->
        send(self(), {__MODULE__, id, image_id})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear-image", _params, socket) do
    send(self(), {__MODULE__, socket.assigns.id, :cleared})
    {:noreply, socket}
  end

  @impl true
  def handle_event("open-picker", _params, socket) do
    available_years = Media.get_available_years()

    {images, _} =
      MediaGalleryCursor.list_page(
        limit: @per_page,
        search: socket.assigns.search,
        start_at_year: socket.assigns.selected_year
      )

    {:noreply,
     socket
     |> assign(:show_modal?, true)
     |> assign(:available_years, available_years)
     |> MediaGalleryCursor.apply_reset_page(images, @per_page, :picker_images)}
  end

  @impl true
  def handle_event("close-picker", _params, socket) do
    {:noreply, assign(socket, :show_modal?, false)}
  end

  @impl true
  def handle_event("search-media", %{"search" => search}, socket) do
    {images, _} =
      MediaGalleryCursor.list_page(
        limit: @per_page,
        search: search,
        start_at_year: socket.assigns.selected_year
      )

    {:noreply,
     MediaGalleryCursor.apply_reset_page(
       assign(socket, :search, search),
       images,
       @per_page,
       :picker_images
     )}
  end

  @impl true
  def handle_event("filter-year", %{"year" => ""}, socket) do
    {images, _} =
      MediaGalleryCursor.list_page(
        limit: @per_page,
        search: socket.assigns.search
      )

    {:noreply,
     MediaGalleryCursor.apply_reset_page(
       assign(socket, :selected_year, nil),
       images,
       @per_page,
       :picker_images
     )}
  end

  @impl true
  def handle_event("filter-year", %{"year" => year_str}, socket) do
    year = String.to_integer(year_str)

    {images, _} =
      MediaGalleryCursor.list_page(
        limit: @per_page,
        search: socket.assigns.search,
        start_at_year: year
      )

    {:noreply,
     MediaGalleryCursor.apply_reset_page(
       assign(socket, :selected_year, year),
       images,
       @per_page,
       :picker_images
     )}
  end

  @impl true
  def handle_event("load-more-media", _params, socket) do
    if socket.assigns.end_of_timeline? do
      {:noreply, socket}
    else
      opts =
        [limit: @per_page, search: socket.assigns.search]
        |> MediaGalleryCursor.cursor_opts_from_assigns(socket.assigns)

      {images, end_of_timeline?} = MediaGalleryCursor.list_page(opts)

      {:noreply,
       socket
       |> assign(:end_of_timeline?, end_of_timeline?)
       |> MediaGalleryCursor.apply_append_page(images, :picker_images)}
    end
  end

  @impl true
  def handle_event("select-image", %{"image-id" => image_id}, socket) do
    send(self(), {__MODULE__, socket.assigns.id, image_id})
    {:noreply, assign(socket, :show_modal?, false)}
  end

  # --- Helpers ---

  defp upload_button_label(count) when count > 1, do: "Upload #{count} photos"
  defp upload_button_label(_count), do: "Upload"

  defp has_image?(id) when is_binary(id) and id != "", do: true
  defp has_image?(_), do: false
end
