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

  The component sends messages to the parent LiveView:
  - `{YscWeb.MediaPickerComponent, id, image_id}` when an image is selected/uploaded
  - `{YscWeb.MediaPickerComponent, id, :cleared}` when the image is cleared
  """
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Ysc.Media

  @per_page 30

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
     |> allow_upload(:media_picker_file,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       auto_upload: true
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
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
              class="flex p-6 flex-col items-center justify-center w-full min-h-52 border-2 border-zinc-300 border-dashed rounded-lg cursor-pointer bg-zinc-50 hover:bg-zinc-100"
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
                          class="group-hover:blur h-60 w-full rounded-lg"
                        />
                      </button>
                    </figure>

                    <%= for err <- upload_errors(@uploads.media_picker_file, entry) do %>
                      <p class="text-sm text-red-600 font-semibold mt-1">
                        <.icon
                          name="hero-exclamation-circle"
                          class="-mt-0.5 h-5 w-5"
                        /> {error_to_string(err)}
                      </p>
                    <% end %>
                  </article>
                <% end %>
              </div>

              <%= for err <- upload_errors(@uploads.media_picker_file) do %>
                <p class="text-sm text-red-600 font-semibold mt-1">
                  <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> {error_to_string(
                    err
                  )}
                </p>
              <% end %>

              <div
                :if={length(@uploads.media_picker_file.entries) == 0}
                class="flex flex-col items-center justify-center pt-3 pb-4"
              >
                <.icon
                  name="hero-cloud-arrow-up"
                  class="w-8 h-10 mb-3 text-zinc-500"
                />
                <p class="mb-1 text-sm text-zinc-500">
                  <span class="font-semibold">Click to upload</span>
                  or drag and drop
                </p>
                <p class="text-xs text-zinc-500">PNG, JPG, JPEG, GIF or WebP</p>
              </div>
            </label>

            <div
              :if={length(@uploads.media_picker_file.entries) > 0}
              class="flex justify-end mt-3"
            >
              <.button type="submit" phx-disable-with="Uploading...">
                Upload
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
          <h2 class="text-lg font-semibold text-zinc-800">
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
    case YscWeb.Uploads.consume_entries(socket, :media_picker_file) do
      [] ->
        {:noreply, socket}

      [image_id] ->
        send(self(), {__MODULE__, socket.assigns.id, image_id})
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

    images =
      Media.list_images_cursor(
        limit: @per_page,
        search: socket.assigns.search,
        start_at_year: socket.assigns.selected_year
      )

    {:noreply,
     socket
     |> assign(:show_modal?, true)
     |> assign(:available_years, available_years)
     |> assign(:end_of_timeline?, length(images) < @per_page)
     |> assign(:last_image_date, last_date(images))
     |> stream(:picker_images, images, reset: true)}
  end

  @impl true
  def handle_event("close-picker", _params, socket) do
    {:noreply, assign(socket, :show_modal?, false)}
  end

  @impl true
  def handle_event("search-media", %{"search" => search}, socket) do
    images =
      Media.list_images_cursor(
        limit: @per_page,
        search: search,
        start_at_year: socket.assigns.selected_year
      )

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:end_of_timeline?, length(images) < @per_page)
     |> assign(:last_image_date, last_date(images))
     |> stream(:picker_images, images, reset: true)}
  end

  @impl true
  def handle_event("filter-year", %{"year" => ""}, socket) do
    images =
      Media.list_images_cursor(limit: @per_page, search: socket.assigns.search)

    {:noreply,
     socket
     |> assign(:selected_year, nil)
     |> assign(:end_of_timeline?, length(images) < @per_page)
     |> assign(:last_image_date, last_date(images))
     |> stream(:picker_images, images, reset: true)}
  end

  @impl true
  def handle_event("filter-year", %{"year" => year_str}, socket) do
    year = String.to_integer(year_str)

    images =
      Media.list_images_cursor(
        limit: @per_page,
        search: socket.assigns.search,
        start_at_year: year
      )

    {:noreply,
     socket
     |> assign(:selected_year, year)
     |> assign(:end_of_timeline?, length(images) < @per_page)
     |> assign(:last_image_date, last_date(images))
     |> stream(:picker_images, images, reset: true)}
  end

  @impl true
  def handle_event("load-more-media", _params, socket) do
    if socket.assigns.end_of_timeline? do
      {:noreply, socket}
    else
      opts =
        [limit: @per_page, search: socket.assigns.search]
        |> maybe_add_cursor(socket.assigns)

      images = Media.list_images_cursor(opts)

      {:noreply,
       socket
       |> assign(:end_of_timeline?, length(images) < @per_page)
       |> assign(:last_image_date, last_date(images))
       |> stream(:picker_images, images)}
    end
  end

  @impl true
  def handle_event("select-image", %{"image-id" => image_id}, socket) do
    send(self(), {__MODULE__, socket.assigns.id, image_id})
    {:noreply, assign(socket, :show_modal?, false)}
  end

  # --- Helpers ---

  defp has_image?(id) when is_binary(id) and id != "", do: true
  defp has_image?(_), do: false

  defp last_date([]), do: nil
  defp last_date(images), do: List.last(images).inserted_at

  defp maybe_add_cursor(opts, %{last_image_date: nil}), do: opts

  defp maybe_add_cursor(opts, %{
         last_image_date: date,
         last_image_id: id,
         selected_year: nil
       })
       when not is_nil(id) do
    opts
    |> Keyword.put(:before_date, date)
    |> Keyword.put(:before_id, id)
  end

  defp maybe_add_cursor(opts, %{last_image_date: date, selected_year: nil}),
    do: Keyword.put(opts, :before_date, date)

  defp maybe_add_cursor(opts, %{
         last_image_date: date,
         last_image_id: id,
         selected_year: year
       })
       when not is_nil(year) and not is_nil(id) do
    opts
    |> Keyword.put(:before_date, date)
    |> Keyword.put(:before_id, id)
    |> Keyword.put(:start_at_year, year)
  end

  defp maybe_add_cursor(opts, %{last_image_date: date, selected_year: year})
       when not is_nil(year) do
    opts
    |> Keyword.put(:before_date, date)
    |> Keyword.put(:start_at_year, year)
  end

  defp error_to_string(:too_large), do: "Too large"

  defp error_to_string(:not_accepted),
    do: "You have selected an unacceptable file type"

  defp error_to_string(:too_many_files), do: "You have selected too many files"
end
