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
     |> assign(:last_image_id, nil)}
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

          <.admin_media_library_browser
            id={@id}
            grid_id={"trix-image-picker-grid-#{@id}"}
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
     |> assign_cursor_from_images(images)
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
     |> assign_cursor_from_images(images)
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
     |> assign_cursor_from_images(images)
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
     |> assign_cursor_from_images(images)
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
       |> assign_cursor_from_images(images)
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

  defp assign_cursor_from_images(socket, []),
    do: socket |> assign(:last_image_date, nil) |> assign(:last_image_id, nil)

  defp assign_cursor_from_images(socket, images) do
    case List.last(images) do
      nil ->
        assign_cursor_from_images(socket, [])

      %{inserted_at: inserted_at, id: id} ->
        socket
        |> assign(:last_image_date, inserted_at)
        |> assign(:last_image_id, id)
    end
  end

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
end
