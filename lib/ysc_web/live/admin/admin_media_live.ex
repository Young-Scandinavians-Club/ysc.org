defmodule YscWeb.AdminMediaLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  import Ecto.Query, only: [from: 2]
  alias Ysc.Repo
  alias Ysc.Media
  alias Ysc.Media.Timeline
  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <.modal
        :if={@live_action == :edit}
        id="update-image-modal"
        on_cancel={JS.navigate(build_media_url_with_state(assigns))}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Edit Image
        </h2>
        <!-- Image Version Tabs -->
        <div class="border-b border-zinc-200 mb-4">
          <nav class="-mb-px flex space-x-4" aria-label="Image Versions">
            <button
              phx-click="select-image-version"
              phx-value-version="optimized"
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_image_version == :optimized,
                  do: "border-blue-500 text-blue-600",
                  else:
                    "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Optimized
              <%= if @active_image.optimized_image_path do %>
                <span class="ml-1 text-xs text-zinc-400">✓</span>
              <% else %>
                <span class="ml-1 text-xs text-zinc-400">—</span>
              <% end %>
            </button>
            <button
              phx-click="select-image-version"
              phx-value-version="thumbnail"
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_image_version == :thumbnail,
                  do: "border-blue-500 text-blue-600",
                  else:
                    "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Thumbnail
              <%= if @active_image.thumbnail_path do %>
                <span class="ml-1 text-xs text-zinc-400">✓</span>
              <% else %>
                <span class="ml-1 text-xs text-zinc-400">—</span>
              <% end %>
            </button>
            <button
              phx-click="select-image-version"
              phx-value-version="raw"
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_image_version == :raw,
                  do: "border-blue-500 text-blue-600",
                  else:
                    "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Raw
              <%= if @active_image.raw_image_path do %>
                <span class="ml-1 text-xs text-zinc-400">✓</span>
              <% else %>
                <span class="ml-1 text-xs text-zinc-400">—</span>
              <% end %>
            </button>
          </nav>
        </div>
        <!-- Image Display -->
        <div class="mb-4">
          <%= if get_image_version_path(@active_image, @selected_image_version) do %>
            <img
              src={get_image_version_path(@active_image, @selected_image_version)}
              class="w-full object-cover rounded max-h-96"
              alt={@active_image.alt_text || @active_image.title || "Image"}
            />
            <div class="mt-2 text-xs text-zinc-500 space-y-1">
              <p>
                <strong>Version:</strong> <%= String.capitalize(
                  Atom.to_string(@selected_image_version)
                ) %>
              </p>
              <%= if @active_image.width && @active_image.height do %>
                <p>
                  <strong>Dimensions:</strong> <%= @active_image.width %> × <%= @active_image.height %> px
                </p>
              <% end %>
              <%= if @active_image.processing_state do %>
                <p>
                  <strong>Processing State:</strong> <%= String.capitalize(
                    Atom.to_string(@active_image.processing_state)
                  ) %>
                </p>
              <% end %>
              <p>
                <strong>Path:</strong>
                <span class="font-mono text-xs break-all">
                  <%= get_image_version_path(@active_image, @selected_image_version) %>
                </span>
              </p>
            </div>
          <% else %>
            <div class="w-full h-64 bg-zinc-100 rounded flex items-center justify-center">
              <div class="text-center">
                <.icon
                  name="hero-photo"
                  class="w-12 h-12 text-zinc-400 mx-auto mb-2"
                />
                <p class="text-sm text-zinc-500">
                  <%= String.capitalize(Atom.to_string(@selected_image_version)) %> version not available
                </p>
              </div>
            </div>
          <% end %>
        </div>

        <p class="leading-6 text-sm text-zinc-600 mt-2">
          Uploaded by <%= "#{String.capitalize(@image_uploader.first_name)} #{String.capitalize(@image_uploader.last_name)} (#{@image_uploader.email}) on #{Timex.format!(@image_uploader.inserted_at, "%Y-%m-%d", :strftime)}" %>
        </p>

        <.simple_form
          for={@form}
          id="edit_image_form"
          phx-submit="save-image"
          phx-change="validate-edit"
        >
          <.input field={@form[:title]} label="Title" />
          <.input field={@form[:alt_text]} label="Alt Text" />

          <div class="flex justify-end">
            <button
              class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-800/80 mr-2"
              phx-click={JS.navigate(build_media_url_with_state(assigns))}
            >
              Cancel
            </button>
            <.button type="submit" phx-disable-with="Updating...">
              Update Image
            </.button>
          </div>
        </.simple_form>
      </.modal>

      <.modal
        :if={@live_action == :upload}
        id="add-images-modal"
        on_cancel={JS.navigate(build_media_url_with_state(assigns))}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Upload new images
        </h2>
        <div class="w-full">
          <form id="upload-form" phx-submit="save" phx-change="validate">
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
                        <.icon
                          name="hero-exclamation-circle"
                          class="-mt-0.5 h-5 w-5"
                        /> <%= error_to_string(err) %>
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
                <.icon
                  name="hero-cloud-arrow-up"
                  class="w-8 h-10 mb-4 text-zinc-500"
                />
                <p class="mb-2 text-sm text-zinc-500">
                  <span class="font-semibold">Click to upload</span>
                  or drag and drop
                </p>
                <p class="text-xs text-zinc-500">
                  SVG, PNG, JPG, JPEG or GIF
                </p>
              </div>
            </label>

            <div class="w-full flex justify-end pt-4">
              <.button
                type="submit"
                phx-disable-with="Uploading..."
                aria-disabled={length(@uploads.media_uploads.entries) == 0}
                disabled={length(@uploads.media_uploads.entries) == 0}
              >
                Upload
              </.button>
            </div>
          </form>
        </div>
      </.modal>

      <div class="flex justify-between items-center py-6">
        <div>
          <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
            Media Library
          </h1>
          <p :if={@media_count > 0} class="text-sm text-zinc-600 mt-1">
            <%= @media_count %> <%= if @media_count == 1,
              do: "image",
              else: "images" %>
          </p>
        </div>

        <div class="flex items-center gap-4">
          <.button phx-click={JS.navigate(~p"/admin/media/upload")}>
            <.icon name="hero-photo" class="w-5 h-5 -mt-1" />
            <span class="ms-1">
              New Image
            </span>
          </.button>
        </div>
      </div>

      <section class="py-6 relative">
        <div
          :if={@media_count > 0}
          id="media-gallery"
          phx-update="stream"
          phx-viewport-bottom={!@end_of_timeline? && "load-more"}
          phx-page-loading
          phx-hook="ScrollPreserver"
          class="space-y-8 pr-12"
        >
          <%= render_images_by_year(assigns) %>
        </div>
        <!-- Year Scrubber -->
        <div
          :if={@media_count > 0 and length(@timeline) > 1}
          id="year-scrubber"
          phx-hook="YearScrubber"
          class="fixed right-4 top-1/2 -translate-y-1/2 z-50 flex flex-col items-center gap-1 py-2 px-1.5 bg-white/95 backdrop-blur-sm rounded-lg shadow-lg border border-zinc-200 transition-all duration-200 hover:shadow-xl"
        >
          <%= for item <- @timeline do %>
            <button
              data-year-item={item.year}
              phx-click="jump-to-year"
              phx-value-year={item.year}
              class="w-9 h-9 flex items-center justify-center text-xs font-semibold text-zinc-600 hover:text-zinc-900 hover:bg-zinc-100 rounded transition-all duration-150 opacity-60 hover:opacity-100 relative group"
              title={"#{item.year} (#{item.count} images)"}
            >
              <span class="group-hover:hidden flex items-center justify-center w-full h-full">
                <%= String.slice(to_string(item.year), -2, 2) %>
              </span>
              <span class="hidden group-hover:flex absolute inset-0 items-center justify-center text-[10px] font-bold whitespace-nowrap px-1">
                <%= item.year %>
              </span>
              <span class="absolute right-full top-1/2 -translate-y-1/2 mr-2 hidden group-hover:block bg-black text-white text-[10px] px-2 py-1 rounded whitespace-nowrap pointer-events-none">
                <%= item.count %> photos
              </span>
            </button>
          <% end %>
        </div>

        <div :if={@media_count == 0} class="mx-auto py-20 text-center">
          <div class="flex flex-col items-center">
            <.icon name="hero-photo" class="w-16 h-16 text-zinc-300 mb-4" />
            <p class="text-lg font-medium text-zinc-700 mb-2">No images yet</p>
            <p class="text-sm text-zinc-500 mb-6">
              Upload your first image to get started
            </p>
            <.button phx-click={JS.navigate(~p"/admin/media/upload")}>
              <.icon name="hero-cloud-arrow-up" class="w-5 h-5 -mt-1" />
              <span class="ms-1">
                Upload Image
              </span>
            </.button>
          </div>
        </div>
      </section>
    </.side_menu>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    image = Media.fetch_image(id)
    image_uploader = Ysc.Accounts.get_user!(image.user_id)
    form = to_form(Media.Image.edit_image_changeset(image, %{}), as: "image")
    media_count = Media.count_images()
    timeline = Media.get_timeline_indices()
    available_years = Enum.map(timeline, & &1.year)

    # Don't load images in mount for edit route - handle_params will load them with correct year
    # This prevents the page from scrolling to top when opening the modal
    {:ok,
     socket
     |> assign(:media_count, media_count)
     |> assign(:page_title, "Media")
     |> assign(:timeline, timeline)
     |> assign(:available_years, available_years)
     |> assign(:selected_year, nil)
     |> assign(:per_page, 30)
     |> assign(:end_of_timeline?, false)
     |> assign(:years_set, MapSet.new())
     |> assign(:years_list, [])
     |> assign(form: form)
     |> assign(:active_image, image)
     |> assign(:image_uploader, image_uploader)
     |> assign(:selected_image_version, :optimized)
     |> assign(:active_page, :media)
     |> stream(:images, [], dom_id: &get_dom_id/1),
     temporary_assigns: [form: nil]}
  end

  @impl true
  def mount(_params, _session, socket) do
    media_count = Media.count_images()
    timeline = Media.get_timeline_indices()
    available_years = Enum.map(timeline, & &1.year)

    # Load default images initially - handle_params will update if year param is present
    # We use an empty stream initially to avoid showing wrong images before handle_params runs
    {:ok,
     socket
     |> assign(:media_count, media_count)
     |> assign(:page_title, "Media")
     |> assign(:active_page, :media)
     |> assign(:timeline, timeline)
     |> assign(:available_years, available_years)
     |> assign(:selected_year, nil)
     |> assign(:per_page, 30)
     |> assign(:end_of_timeline?, false)
     |> assign(:years_set, MapSet.new())
     |> assign(:years_list, [])
     |> assign(:uploaded_files, [])
     |> stream(:images, [], dom_id: &get_dom_id/1)
     |> allow_upload(:media_uploads,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 10,
       external: &presign_upload/2
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    require Logger

    Logger.debug(
      "handle_params called with params: #{inspect(params)}, uri: #{inspect(uri)}"
    )

    # Parse query parameters from URI to get year param
    query_params = parse_query_params_from_uri(params, uri)
    year_param = query_params["year"] || query_params[:year]

    # Store current URL parameters in assigns for use when building return URLs
    socket = assign(socket, :url_year_param, year_param)

    Logger.debug("Year param: #{inspect(year_param)}")

    # Load images based on year param, even when on edit route
    # But only load if stream is empty or year has changed
    socket =
      if year_param do
        year =
          if is_binary(year_param),
            do: String.to_integer(year_param),
            else: year_param

        Logger.debug(
          "Processing year: #{year}, current: #{socket.assigns.selected_year}"
        )

        # Only reload if year changed OR if stream is empty (e.g., on edit route mount)
        stream_empty = Enum.empty?(socket.assigns.streams.images.inserts)
        year_changed = year != socket.assigns.selected_year

        if year_changed || stream_empty do
          start_date =
            DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC")

          end_date =
            DateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59], "Etc/UTC")

          images =
            Repo.all(
              from i in Media.Image,
                where:
                  i.inserted_at >= ^start_date and i.inserted_at <= ^end_date,
                order_by: [desc: i.inserted_at, desc: i.id],
                limit: ^socket.assigns.per_page
            )

          Logger.debug("Loaded #{length(images)} images for year #{year}")

          stream_items = Timeline.inject_date_headers(images)

          new_years =
            Enum.map(images, fn image -> image.inserted_at.year end)
            |> MapSet.new()

          years_list = new_years |> MapSet.to_list() |> Enum.sort(:desc)

          socket
          |> assign(:selected_year, year)
          |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
          |> assign(:years_set, new_years)
          |> assign(:years_list, years_list)
          |> stream(:images, stream_items, reset: true, dom_id: &get_dom_id/1)
          |> update_years_from_stream()
        else
          socket
        end
      else
        # If no year param, load default images (all images, most recent first)
        # Check if we already have images loaded (to avoid reloading unnecessarily)
        stream_empty = Enum.empty?(socket.assigns.streams.images.inserts)
        has_year_filter = not is_nil(socket.assigns.selected_year)

        if has_year_filter || stream_empty do
          images = Media.list_images_cursor(limit: socket.assigns.per_page)
          stream_items = Timeline.inject_date_headers(images)

          new_years =
            Enum.map(images, fn image -> image.inserted_at.year end)
            |> MapSet.new()

          years_list = new_years |> MapSet.to_list() |> Enum.sort(:desc)

          socket
          |> assign(:selected_year, nil)
          |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
          |> assign(:years_set, new_years)
          |> assign(:years_list, years_list)
          |> stream(:images, stream_items, reset: true, dom_id: &get_dom_id/1)
          |> update_years_from_stream()
        else
          socket
        end
      end

    {:noreply, socket}
  end

  defp parse_query_params_from_uri(params, uri) do
    cond do
      is_binary(uri) ->
        # URI is a string, parse it first
        case URI.parse(uri) do
          %URI{query: query} when is_binary(query) and query != "" ->
            # Use URI.decode_query which handles encoding properly
            try do
              decoded_params = URI.decode_query(query)
              Map.merge(params, decoded_params)
            rescue
              _ ->
                # Fallback to manual parsing
                query
                |> String.split("&")
                |> Enum.reduce(params, fn pair, acc ->
                  case String.split(pair, "=", parts: 2) do
                    [key, value] ->
                      decoded_key = URI.decode(key)
                      decoded_value = URI.decode(value)
                      Map.put(acc, decoded_key, decoded_value)

                    [key] ->
                      decoded_key = URI.decode(key)
                      Map.put(acc, decoded_key, "")
                  end
                end)
            end

          _ ->
            params
        end

      is_struct(uri, URI) && uri.query && uri.query != "" ->
        # Parse query string from URI struct
        try do
          decoded_params = URI.decode_query(uri.query)
          Map.merge(params, decoded_params)
        rescue
          _ ->
            # Fallback to manual parsing
            uri.query
            |> String.split("&")
            |> Enum.reduce(params, fn pair, acc ->
              case String.split(pair, "=", parts: 2) do
                [key, value] ->
                  decoded_key = URI.decode(key)
                  decoded_value = URI.decode(value)
                  Map.put(acc, decoded_key, decoded_value)

                [key] ->
                  decoded_key = URI.decode(key)
                  Map.put(acc, decoded_key, "")
              end
            end)
        end

      true ->
        # Use params as-is if no query string
        params
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media_uploads, ref)}
  end

  def handle_event("save", _params, socket) do
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

    # Reload images after upload
    media_count = Media.count_images()
    timeline = Media.get_timeline_indices()
    available_years = Enum.map(timeline, & &1.year)
    images = Media.list_images_cursor(limit: socket.assigns.per_page)
    stream_items = Timeline.inject_date_headers(images)

    {:noreply,
     socket
     |> update(:uploaded_files, &(&1 ++ uploaded_files))
     |> assign(:media_count, media_count)
     |> assign(:timeline, timeline)
     |> assign(:available_years, available_years)
     |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
     |> assign(:years_set, MapSet.new())
     |> assign(:years_list, [])
     |> stream(:images, stream_items, reset: true, dom_id: &get_dom_id/1)
     |> update_years_from_stream()
     |> push_navigate(to: ~p"/admin/media")}
  end

  def handle_event("validate-edit", %{"image" => image_params}, socket) do
    form_data =
      Media.Image.edit_image_changeset(
        socket.assigns[:active_image],
        image_params
      )

    {:noreply,
     socket
     |> assign(
       form: to_form(Map.put(form_data, :action, :validate), as: "image")
     )}
  end

  def handle_event("save-image", %{"image" => image_params}, socket) do
    current_user = socket.assigns[:current_user]
    active_image = socket.assigns[:active_image]

    Media.update_image(active_image, image_params, current_user)

    # Reload images after update
    timeline = Media.get_timeline_indices()
    available_years = Enum.map(timeline, & &1.year)
    images = Media.list_images_cursor(limit: socket.assigns.per_page)
    stream_items = Timeline.inject_date_headers(images)

    {:noreply,
     socket
     |> assign(:timeline, timeline)
     |> assign(:available_years, available_years)
     |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
     |> assign(:years_set, MapSet.new())
     |> assign(:years_list, [])
     |> stream(:images, stream_items, reset: true, dom_id: &get_dom_id/1)
     |> update_years_from_stream()
     |> push_navigate(to: build_media_url_with_state(socket))}
  end

  def handle_event("select-image-version", %{"version" => version}, socket) do
    version_atom =
      case version do
        "thumbnail" -> :thumbnail
        "optimized" -> :optimized
        "raw" -> :raw
        _ -> :thumbnail
      end

    {:noreply, assign(socket, :selected_image_version, version_atom)}
  end

  def handle_event("filter_by_year", %{"year" => ""}, socket) do
    images = Media.list_images_cursor(limit: socket.assigns.per_page)
    stream_items = Timeline.inject_date_headers(images)

    new_years =
      Enum.map(images, fn image -> image.inserted_at.year end) |> MapSet.new()

    years_list = new_years |> MapSet.to_list() |> Enum.sort(:desc)

    {:noreply,
     socket
     |> assign(:selected_year, nil)
     |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
     |> assign(:years_set, new_years)
     |> assign(:years_list, years_list)
     |> stream(:images, stream_items, reset: true, dom_id: &get_dom_id/1)}
  end

  def handle_event("filter_by_year", %{"year" => year_str}, socket) do
    year = String.to_integer(year_str)
    start_date = DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC")
    end_date = DateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59], "Etc/UTC")

    images =
      Repo.all(
        from i in Media.Image,
          where: i.inserted_at >= ^start_date and i.inserted_at <= ^end_date,
          order_by: [desc: i.inserted_at, desc: i.id],
          limit: ^socket.assigns.per_page
      )

    stream_items = Timeline.inject_date_headers(images)

    new_years =
      Enum.map(images, fn image -> image.inserted_at.year end) |> MapSet.new()

    years_list = new_years |> MapSet.to_list() |> Enum.sort(:desc)

    {:noreply,
     socket
     |> assign(:selected_year, year)
     |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
     |> assign(:years_set, new_years)
     |> assign(:years_list, years_list)
     |> stream(:images, stream_items, reset: true, dom_id: &get_dom_id/1)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    require Logger

    # Safety check: ensure we have images in the stream before trying to load more
    current_count = Enum.count(socket.assigns.streams.images.inserts)

    Logger.debug(
      "Load-more: current stream count: #{current_count}, end_of_timeline: #{socket.assigns.end_of_timeline?}"
    )

    if not socket.assigns.end_of_timeline? and current_count > 0 do
      # Get the last image's inserted_at as cursor (skip headers)
      last_image_date =
        socket.assigns.streams.images.inserts
        |> Enum.filter(fn {_id, _at, item, _meta} ->
          match?(%Media.Image{}, item)
        end)
        |> List.last()
        |> case do
          nil -> nil
          {_id, _at, image, _meta} -> image.inserted_at
        end

      Logger.debug(
        "Load-more: last_image_date=#{inspect(last_image_date)}, selected_year=#{inspect(socket.assigns.selected_year)}"
      )

      new_images =
        if last_image_date do
          # If a year filter is active, load images from that year only
          if socket.assigns.selected_year do
            year = socket.assigns.selected_year

            start_date =
              DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC")

            end_date =
              DateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59], "Etc/UTC")

            images =
              Repo.all(
                from i in Media.Image,
                  where:
                    i.inserted_at >= ^start_date and i.inserted_at <= ^end_date and
                      i.inserted_at < ^last_image_date,
                  order_by: [desc: i.inserted_at, desc: i.id],
                  limit: ^socket.assigns.per_page
              )

            Logger.debug(
              "Load-more: loaded #{length(images)} images for year #{year}"
            )

            images
          else
            images =
              Media.list_images_cursor(
                before_date: last_image_date,
                limit: socket.assigns.per_page
              )

            Logger.debug(
              "Load-more: loaded #{length(images)} images (no year filter)"
            )

            images
          end
        else
          Logger.warning(
            "Load-more: no last_image_date found, cannot load more"
          )

          []
        end

      case new_images do
        [] ->
          Logger.debug("Load-more: no new images, marking end_of_timeline")
          {:noreply, assign(socket, :end_of_timeline?, true)}

        [_ | _] = new_images ->
          # Get the last image (not header) to determine if we need a new header
          last_existing_image_date =
            socket.assigns.streams.images.inserts
            |> Enum.filter(fn {_id, _at, item, _meta} ->
              match?(%Media.Image{}, item)
            end)
            |> List.last()
            |> case do
              nil -> nil
              {_id, _at, image, _meta} -> image.inserted_at
            end

          # Only inject headers if we're starting a new month
          # Check if the first new image is in a different month than the last image
          first_new_image_date = List.first(new_images).inserted_at

          needs_header =
            case last_existing_image_date do
              nil ->
                true

              last_date ->
                last_date.year != first_new_image_date.year ||
                  last_date.month != first_new_image_date.month
            end

          # Only proceed if we have items to add
          if Enum.any?(new_images) do
            stream_items =
              if needs_header do
                Timeline.inject_date_headers(new_images)
              else
                # No header needed, just add the images
                new_images
              end

            Logger.debug(
              "Load-more: adding #{length(stream_items)} items to stream (needs_header: #{needs_header})"
            )

            # Extract years from new images and update
            new_years =
              Enum.map(new_images, fn image -> image.inserted_at.year end)
              |> MapSet.new()

            existing_years = Map.get(socket.assigns, :years_set, MapSet.new())
            updated_years = MapSet.union(existing_years, new_years)

            # Make sure we're appending, not resetting
            # Use dom_id to ensure proper stream tracking
            # Only stream if we have items
            {:noreply,
             socket
             |> assign(
               :end_of_timeline?,
               length(new_images) < socket.assigns.per_page
             )
             |> assign(:years_set, updated_years)
             |> update_years_from_stream()
             |> stream(:images, stream_items, at: -1, dom_id: &get_dom_id/1)}
          else
            Logger.warning(
              "Load-more: new_images list is empty, marking end_of_timeline"
            )

            {:noreply, assign(socket, :end_of_timeline?, true)}
          end
      end
    else
      Logger.debug("Load-more: end_of_timeline is true, ignoring")
      {:noreply, socket}
    end
  end

  def handle_event("jump-to-year", %{"year" => year}, socket) do
    year_int = if is_binary(year), do: String.to_integer(year), else: year

    # Load images starting from this year using cursor-based pagination
    images =
      Media.list_images_cursor(
        start_at_year: year_int,
        limit: socket.assigns.per_page
      )

    stream_items = Timeline.inject_date_headers(images)

    # Extract years from loaded images
    new_years =
      Enum.map(images, fn image -> image.inserted_at.year end) |> MapSet.new()

    years_list = new_years |> MapSet.to_list() |> Enum.sort(:desc)

    # Update URL with year parameter
    socket =
      socket
      # Set the selected year to maintain filter state
      |> assign(:selected_year, year_int)
      |> assign(:url_year_param, to_string(year_int))
      |> assign(:years_set, new_years)
      |> assign(:years_list, years_list)
      |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
      |> stream(:images, stream_items, reset: true, dom_id: &get_dom_id/1)
      |> update_years_from_stream()

    # Build URL with year parameter
    url = build_media_url_with_state(socket)

    socket =
      socket
      |> push_patch(to: url)
      |> push_event("scroll-to-year", %{year: year_int})

    {:noreply, socket}
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

  defp error_to_string(:external_client_failure) do
    "Upload failed: The file could not be uploaded to storage. " <>
      "This may be due to network issues, CORS configuration, or invalid credentials. " <>
      "Please check the browser console for more details."
  end

  defp error_to_string(_), do: "An error occurred"

  # Helper function to get a specific image version path
  defp get_image_version_path(%Media.Image{} = image, :thumbnail) do
    image.thumbnail_path
  end

  defp get_image_version_path(%Media.Image{} = image, :optimized) do
    image.optimized_image_path
  end

  defp get_image_version_path(%Media.Image{} = image, :raw) do
    image.raw_image_path
  end

  defp get_image_version_path(_, _), do: nil

  # Helper functions for image display (similar to GalleryComponent)
  defp get_blur_hash(%Media.Image{blur_hash: nil}),
    do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp get_blur_hash(%Media.Image{blur_hash: blur_hash}), do: blur_hash

  defp get_image_path(%Media.Image{thumbnail_path: nil} = image),
    do: image.raw_image_path

  defp get_image_path(%Media.Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp get_image_path(%Media.Image{thumbnail_path: thumbnail_path}),
    do: thumbnail_path

  defp get_image_path(%Media.Image{optimized_image_path: optimized_path}),
    do: optimized_path

  # Get DOM ID for stream items (headers or images)
  defp get_dom_id(%Timeline.Header{} = header), do: header.id
  defp get_dom_id(%Media.Image{} = image), do: "image-#{image.id}"

  defp build_media_url_with_state(assigns_or_socket) do
    # Handle both socket and assigns map
    assigns =
      if is_map(assigns_or_socket) && Map.has_key?(assigns_or_socket, :assigns),
        do: assigns_or_socket.assigns,
        else: assigns_or_socket

    # Prefer url_year_param (from URL) over selected_year (from state)
    # url_year_param is already a string, selected_year is an integer
    # Decode if already encoded to avoid double encoding
    year =
      case assigns[:url_year_param] do
        nil ->
          if assigns[:selected_year],
            do: to_string(assigns[:selected_year]),
            else: nil

        year_str when is_binary(year_str) ->
          # Decode if encoded, then we'll encode it properly
          try do
            URI.decode(year_str)
          rescue
            _ -> year_str
          end

        _ ->
          nil
      end

    query_params = []

    query_params =
      if year, do: [{"year", year} | query_params], else: query_params

    base_path = ~p"/admin/media"

    if Enum.any?(query_params) do
      query_string = URI.encode_query(query_params)
      "#{base_path}?#{query_string}"
    else
      base_path
    end
  end

  defp build_image_edit_url_with_state(assigns, image_id) do
    # Build URL for image edit modal with state parameters preserved
    # Always use selected_year if available (it's the current filter state)
    # url_year_param might not be set if handle_params hasn't run yet
    # Decode if already encoded to avoid double encoding
    year =
      case {assigns[:url_year_param], assigns[:selected_year]} do
        {year_str, _} when is_binary(year_str) and year_str != "" ->
          # Decode if encoded, then we'll encode it properly
          try do
            URI.decode(year_str)
          rescue
            _ -> year_str
          end

        {_, selected_year} when not is_nil(selected_year) ->
          to_string(selected_year)

        _ ->
          nil
      end

    query_params = []

    query_params =
      if year, do: [{"year", year} | query_params], else: query_params

    base_path = ~p"/admin/media/upload/#{image_id}"

    if Enum.any?(query_params) do
      query_string = URI.encode_query(query_params)
      "#{base_path}?#{query_string}"
    else
      base_path
    end
  end

  # Update years from stream
  defp update_years_from_stream(socket) do
    years =
      socket.assigns.streams.images.inserts
      |> Enum.filter(fn {_id, _at, item, _meta} ->
        match?(%Media.Image{}, item)
      end)
      |> Enum.map(fn {_id, _at, image, _meta} -> image.inserted_at.year end)
      |> MapSet.new()
      |> MapSet.to_list()
      |> Enum.sort(:desc)

    socket
    |> assign(:years_set, MapSet.new(years))
    |> assign(:years_list, years)
  end

  # Render images with date headers from stream
  defp render_images_by_year(assigns) do
    # Extract unique years from streamed images (excluding headers)
    years =
      assigns.streams.images.inserts
      |> Enum.filter(fn {_id, _at, item, _meta} ->
        match?(%Media.Image{}, item)
      end)
      |> Enum.map(fn {_id, _at, image, _meta} -> image.inserted_at.year end)
      |> Enum.uniq()
      |> Enum.sort(:desc)

    assigns = assign(assigns, :years, years)

    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 3xl:grid-cols-7 4xl:grid-cols-9 gap-3 md:gap-4">
      <%= for {id, item} <- @streams.images do %>
        <%!-- RENDER HEADER --%>
        <%= if match?(%Timeline.Header{}, item) do %>
          <div
            id={id}
            data-year-section={item.date.year}
            class="col-span-full sticky top-0 z-10 bg-white/95 backdrop-blur py-4 px-4 mt-4 font-bold text-xl border-b border-zinc-200"
          >
            <%= item.formatted_date %>
          </div>
        <% end %>

        <%!-- RENDER IMAGE --%>
        <%= if match?(%Media.Image{}, item) do %>
          <button
            phx-click={
              JS.navigate(build_image_edit_url_with_state(assigns, item.id))
            }
            id={id}
            class="mb-4 group relative w-full rounded-lg aspect-square border border-zinc-200 cursor-pointer hover:border-zinc-400 hover:shadow-md transition-all duration-200 overflow-hidden"
          >
            <canvas
              id={"blur-hash-image-#{item.id}"}
              src={get_blur_hash(item)}
              class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
              phx-hook="BlurHashCanvas"
            >
            </canvas>

            <img
              class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out rounded-lg w-full h-full object-cover group-hover:opacity-100"
              id={"img-#{item.id}"}
              src={get_image_path(item)}
              loading="lazy"
              phx-hook="BlurHashImage"
              alt={item.alt_text || item.title || "Image"}
            />

            <div
              :if={item.title != nil or item.alt_text != nil}
              class="absolute z-[2] hidden group-hover:block inset-x-0 bottom-0 px-2 py-2 bg-gradient-to-t from-zinc-900/90 via-zinc-900/80 to-transparent"
            >
              <p
                :if={item.title != nil}
                class="text-xs font-medium text-white truncate"
                title={item.title}
              >
                <%= item.title %>
              </p>
              <p
                :if={item.title == nil and item.alt_text != nil}
                class="text-xs font-medium text-white/90 truncate"
                title={item.alt_text}
              >
                <%= item.alt_text %>
              </p>
            </div>
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end
end
