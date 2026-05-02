defmodule YscWeb.TrixImagePickerComponent do
  @moduledoc """
  A LiveComponent that provides an "Insert from library" button for Trix editors.

  Opens a searchable/filterable media library modal and sends the selected
  `%Media.Image{}` struct back to the parent LiveView so it can push a JS event
  to insert the image into the Trix editor body.

  ## Usage

      <.live_component
        module={YscWeb.TrixImagePickerComponent}
        id={:post_body_image_picker}
        target_input_id="post[raw_body]"
      />

  The component sends `{YscWeb.TrixImagePickerComponent, id, %Media.Image{}}` to
  the parent LiveView when an image is selected.
  """
  use YscWeb, :live_component

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
     |> assign(:last_image_date, nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:disabled?, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"trix-image-picker-#{@id}"} class="not-prose">
      <button
        :if={!@disabled?}
        type="button"
        phx-click="open-picker"
        phx-target={@myself}
        data-trix-library-trigger={@target_input_id}
        class="hidden"
      >
        Insert from library
      </button>

      <.modal
        :if={@show_modal?}
        id={"trix-image-picker-modal-#{@id}"}
        show
        on_cancel={JS.push("close-picker", target: @myself)}
        max_width="max-w-5xl"
      >
        <div class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800">
            Insert image from library
          </h2>

          <div class="flex flex-col sm:flex-row gap-3">
            <form phx-change="search-media" phx-target={@myself} class="flex-1">
              <.input
                type="text"
                name="search"
                value={@search}
                placeholder="Search by title or alt text..."
                phx-debounce="300"
              />
            </form>

            <div class="flex flex-wrap gap-1.5 items-center">
              <button
                type="button"
                phx-click="filter-year"
                phx-target={@myself}
                phx-value-year=""
                class={[
                  "text-xs font-medium px-2.5 py-1 rounded-full transition",
                  if(@selected_year == nil,
                    do: "bg-zinc-800 text-white",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                All
              </button>
              <%= for year <- @available_years do %>
                <button
                  type="button"
                  phx-click="filter-year"
                  phx-target={@myself}
                  phx-value-year={year}
                  class={[
                    "text-xs font-medium px-2.5 py-1 rounded-full transition",
                    if(@selected_year == year,
                      do: "bg-zinc-800 text-white",
                      else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                    )
                  ]}
                >
                  {year}
                </button>
              <% end %>
            </div>
          </div>

          <div
            id={"trix-image-picker-grid-#{@id}"}
            phx-update="stream"
            phx-viewport-bottom="load-more-media"
            phx-target={@myself}
            class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-2 max-h-[60vh] overflow-y-auto pr-1"
          >
            <button
              :for={{dom_id, image} <- @streams.picker_images}
              type="button"
              id={dom_id}
              phx-click="select-image"
              phx-target={@myself}
              phx-value-image-id={image.id}
              class="group relative aspect-square rounded-lg overflow-hidden border-2 border-transparent hover:border-blue-500 focus:border-blue-500 focus:outline-none transition p-0"
            >
              <img
                src={thumbnail_url(image)}
                alt={image.alt_text || image.title || "Image"}
                loading="lazy"
                class="absolute inset-0 w-full h-full object-cover"
              />
              <div
                :if={image.title}
                class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent p-1.5 opacity-0 group-hover:opacity-100 transition"
              >
                <p class="text-xs text-white truncate">{image.title}</p>
              </div>
            </button>
          </div>

          <p :if={@end_of_timeline?} class="text-center text-xs text-zinc-400 py-2">
            No more images
          </p>
        </div>
      </.modal>
    </div>
    """
  end

  # --- Events ---

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
    image = Media.get_image!(image_id)
    send(self(), {__MODULE__, socket.assigns.id, image})
    {:noreply, assign(socket, :show_modal?, false)}
  end

  # --- Helpers ---

  defp last_date([]), do: nil
  defp last_date(images), do: List.last(images).inserted_at

  defp maybe_add_cursor(opts, %{last_image_date: nil}), do: opts

  defp maybe_add_cursor(opts, %{last_image_date: date, selected_year: nil}),
    do: Keyword.put(opts, :before_date, date)

  defp maybe_add_cursor(opts, %{last_image_date: date, selected_year: _year}),
    do: Keyword.put(opts, :before_date, date)

  defp thumbnail_url(%{thumbnail_path: path})
       when is_binary(path) and path != "", do: path

  defp thumbnail_url(%{optimized_image_path: path})
       when is_binary(path) and path != "", do: path

  defp thumbnail_url(%{raw_image_path: path})
       when is_binary(path) and path != "", do: path

  defp thumbnail_url(_), do: "/images/ysc_logo.webp"
end
