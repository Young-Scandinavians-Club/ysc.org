defmodule YscWeb.AdminMediaLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

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
      user={@current_user}
      role={@admin_role}
    >
      <.modal
        :if={@live_action == :edit}
        id="update-image-modal"
        on_cancel={JS.patch(build_media_url_with_state(assigns))}
        show
      >
        <.admin_page_title level={2} class="mb-6">
          Edit Image
        </.admin_page_title>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Left Column: Image Preview --%>
          <div>
            <%!-- Image Version Tabs --%>
            <div class="border-b border-zinc-200 mb-4 w-full min-w-0 overflow-x-auto">
              <nav
                class="-mb-px flex space-x-2 flex-nowrap"
                aria-label="Image Versions"
              >
                <button
                  phx-click="select-image-version"
                  phx-value-version="optimized"
                  class={[
                    "flex flex-col items-center py-2 px-3 border-b-2 font-medium text-xs transition-all rounded-t",
                    if(@selected_image_version == :optimized,
                      do: "border-blue-500 text-blue-600 bg-blue-50",
                      else:
                        "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300 hover:bg-zinc-50"
                    )
                  ]}
                >
                  <div class={[
                    "mb-1 flex h-10 w-10 items-center justify-center rounded-full border",
                    if(@active_image.optimized_image_path,
                      do: "border-blue-200 bg-blue-50 text-blue-600",
                      else: "border-zinc-200 bg-zinc-100 text-zinc-400"
                    )
                  ]}>
                    <.icon name="hero-sparkles" class="h-5 w-5" />
                  </div>
                  <span>Optimized</span>
                </button>
                <button
                  phx-click="select-image-version"
                  phx-value-version="thumbnail"
                  class={[
                    "flex flex-col items-center py-2 px-3 border-b-2 font-medium text-xs transition-all rounded-t",
                    if(@selected_image_version == :thumbnail,
                      do: "border-blue-500 text-blue-600 bg-blue-50",
                      else:
                        "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300 hover:bg-zinc-50"
                    )
                  ]}
                >
                  <div class={[
                    "mb-1 flex h-10 w-10 items-center justify-center rounded-full border",
                    if(@active_image.thumbnail_path,
                      do: "border-emerald-200 bg-emerald-50 text-emerald-600",
                      else: "border-zinc-200 bg-zinc-100 text-zinc-400"
                    )
                  ]}>
                    <.icon name="hero-squares-2x2" class="h-5 w-5" />
                  </div>
                  <span>Thumbnail</span>
                </button>
                <button
                  phx-click="select-image-version"
                  phx-value-version="raw"
                  class={[
                    "flex flex-col items-center py-2 px-3 border-b-2 font-medium text-xs transition-all rounded-t",
                    if(@selected_image_version == :raw,
                      do: "border-blue-500 text-blue-600 bg-blue-50",
                      else:
                        "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300 hover:bg-zinc-50"
                    )
                  ]}
                >
                  <div class={[
                    "mb-1 flex h-10 w-10 items-center justify-center rounded-full border",
                    if(@active_image.raw_image_path,
                      do: "border-zinc-300 bg-zinc-50 text-zinc-700",
                      else: "border-zinc-200 bg-zinc-100 text-zinc-400"
                    )
                  ]}>
                    <.icon name="hero-photo" class="h-5 w-5" />
                  </div>
                  <span>Raw</span>
                </button>
              </nav>
            </div>

            <%!-- Image Display --%>
            <%= if get_image_version_path(@active_image, @selected_image_version) do %>
              <img
                src={get_image_version_path(@active_image, @selected_image_version)}
                class="w-full object-contain rounded max-h-96 border border-zinc-200"
                alt={@active_image.alt_text || @active_image.title || "Image"}
              />

              <%!-- Quick Copy Actions --%>
              <div class="mt-3 flex flex-wrap gap-2">
                <button
                  type="button"
                  id="copy-path-btn"
                  phx-hook="ClipboardCopy"
                  data-copy-target={"image-path-text-#{@selected_image_version}"}
                  data-copy-feedback="copy-path-btn-feedback"
                  class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-zinc-300 hover:border-zinc-400 hover:bg-zinc-50 rounded transition-colors"
                  title="Copy URL to clipboard"
                >
                  <.icon name="hero-link" class="w-3.5 h-3.5" /> Copy URL
                  <span
                    id="copy-path-btn-feedback"
                    class="hidden items-center gap-1 text-green-700"
                    aria-live="polite"
                  >
                    <.icon name="hero-check" class="h-3.5 w-3.5" />
                    <span data-copy-feedback-label>Copied</span>
                  </span>
                </button>
                <button
                  type="button"
                  id="copy-markdown-btn"
                  phx-hook="ClipboardCopy"
                  data-copy-target={"image-markdown-#{@selected_image_version}"}
                  data-copy-feedback="copy-markdown-btn-feedback"
                  class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-zinc-300 hover:border-zinc-400 hover:bg-zinc-50 rounded transition-colors"
                  title="Copy as Markdown"
                >
                  <.icon name="hero-document-text" class="w-3.5 h-3.5" />
                  Copy Markdown
                  <span
                    id="copy-markdown-btn-feedback"
                    class="hidden items-center gap-1 text-green-700"
                    aria-live="polite"
                  >
                    <.icon name="hero-check" class="h-3.5 w-3.5" />
                    <span data-copy-feedback-label>Copied</span>
                  </span>
                </button>
                <button
                  type="button"
                  id="copy-html-btn"
                  phx-hook="ClipboardCopy"
                  data-copy-target={"image-html-#{@selected_image_version}"}
                  data-copy-feedback="copy-html-btn-feedback"
                  class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-zinc-300 hover:border-zinc-400 hover:bg-zinc-50 rounded transition-colors"
                  title="Copy as HTML"
                >
                  <.icon name="hero-code-bracket" class="w-3.5 h-3.5" /> Copy HTML
                  <span
                    id="copy-html-btn-feedback"
                    class="hidden items-center gap-1 text-green-700"
                    aria-live="polite"
                  >
                    <.icon name="hero-check" class="h-3.5 w-3.5" />
                    <span data-copy-feedback-label>Copied</span>
                  </span>
                </button>
                <input
                  type="hidden"
                  id={"image-path-text-#{@selected_image_version}"}
                  value={
                    get_image_version_path(@active_image, @selected_image_version)
                  }
                />
                <input
                  type="hidden"
                  id={"image-markdown-#{@selected_image_version}"}
                  value={"![#{markdown_alt_text(@active_image)}](#{get_image_version_path(@active_image, @selected_image_version)})"}
                />
                <input
                  type="hidden"
                  id={"image-html-#{@selected_image_version}"}
                  value={"<img src=\"#{get_image_version_path(@active_image, @selected_image_version)}\" alt=\"#{html_alt_text(@active_image)}\" />"}
                />
              </div>

              <%!-- Image Metadata --%>
              <div class="mt-4 text-xs text-zinc-500 space-y-1 bg-zinc-50 p-3 rounded">
                <p>
                  <strong>Version:</strong>
                  {String.capitalize(Atom.to_string(@selected_image_version))}
                </p>
                <%= if @selected_image_version == :optimized && @active_image.width && @active_image.height do %>
                  <p>
                    <strong>Dimensions:</strong>
                    {@active_image.width} × {@active_image.height} px
                  </p>
                <% end %>
                <%= if @active_image.processing_state do %>
                  <p>
                    <strong>Status:</strong>
                    {String.capitalize(
                      Atom.to_string(@active_image.processing_state)
                    )}
                  </p>
                <% end %>
                <p class="break-all">
                  <strong>Path:</strong>
                  <span class="font-mono">
                    {get_image_version_path(@active_image, @selected_image_version)}
                  </span>
                </p>
              </div>

              <p class="text-xs text-zinc-500 mt-3">
                Uploaded by {"#{Ysc.title_case(@image_uploader.first_name)} #{Ysc.title_case(@image_uploader.last_name)} on #{Timex.format!(@active_image.inserted_at, "%b %d, %Y", :strftime)}"}
              </p>
            <% else %>
              <div class="w-full h-64 bg-zinc-100 rounded flex items-center justify-center">
                <div class="text-center">
                  <.icon
                    name="hero-photo"
                    class="w-12 h-12 text-zinc-400 mx-auto mb-2"
                  />
                  <p class="text-sm text-zinc-500">
                    {String.capitalize(Atom.to_string(@selected_image_version))} version not available
                  </p>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Right Column: Edit Form --%>
          <div>
            <.simple_form
              for={@form}
              id="edit_image_form"
              phx-submit="save-image"
              phx-change="validate-edit"
            >
              <.input field={@form[:title]} label="Title" />
              <.input field={@form[:alt_text]} label="Alt Text" />

              <div class="flex justify-end gap-2 mt-4">
                <button
                  type="button"
                  class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-800/80"
                  phx-click={JS.patch(build_media_url_with_state(assigns))}
                >
                  Cancel
                </button>
                <.button type="submit" phx-disable-with="Updating...">
                  Update Image
                </.button>
              </div>
            </.simple_form>
          </div>
        </div>
      </.modal>

      <.modal
        :if={@live_action == :upload}
        id="add-images-modal"
        on_cancel={JS.patch(build_media_url_with_state(assigns))}
        show
      >
        <.admin_page_title level={2} class="mb-4">
          Upload new images
        </.admin_page_title>
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
                          class="group-hover:blur h-[120px] w-[120px]"
                        />
                        <figcaption class="text-sm truncate overflow-hidden bg-zinc-100 text-zinc-600 w-28 z-8 absolute inset-x-0 bottom-0 py-1">
                          {entry.client_name}
                        </figcaption>
                      </button>
                    </figure>

                    <%!-- Phoenix.Component.upload_errors/2 returns a list of error atoms --%>
                    <%= for err <- upload_errors(@uploads.media_uploads, entry) do %>
                      <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
                        <.icon
                          name="hero-exclamation-circle"
                          class="-mt-0.5 h-5 w-5"
                        /> {error_to_string(err)}
                      </p>
                    <% end %>
                  </article>
                <% end %>
              </div>

              <%!-- Phoenix.Component.upload_errors/1 returns a list of error atoms --%>
              <%= for err <- upload_errors(@uploads.media_uploads) do %>
                <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
                  <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> {error_to_string(
                    err
                  )}
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

      <form
        :if={@live_action != :upload}
        id="media-drop-upload-form"
        phx-change="validate"
        class="hidden"
      >
        <.live_file_input upload={@uploads.media_drop_uploads} />
      </form>

      <div
        id="media-page-drop-target"
        phx-hook="MediaDropZone"
        phx-drop-target={@uploads.media_drop_uploads.ref}
      >
        <div class="flex flex-col gap-4 py-6 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <div class="flex items-center gap-2">
              <.admin_page_title>Media Library</.admin_page_title>
              <.admin_help_link
                topic="media/upload"
                label="Media help"
                role={@admin_role}
              />
            </div>
            <p :if={@media_count > 0} class="text-sm text-zinc-600 mt-1">
              {@media_count} {if @media_count == 1,
                do: "image",
                else: "images"}
            </p>
          </div>

          <div class="flex w-full items-center justify-between gap-3 sm:w-auto sm:justify-start sm:shrink-0">
            <div
              :if={@media_count > 0}
              id="media-layout-preference"
              phx-hook="MediaLayoutPreference"
              class="inline-flex rounded-lg border border-zinc-300 bg-zinc-100 p-1"
              role="group"
              aria-label="Media layout"
            >
              <button
                type="button"
                phx-click="set-layout"
                phx-value-layout="square"
                data-media-layout="square"
                aria-pressed={
                  if(@layout_mode == :square, do: "true", else: "false")
                }
                class={[
                  "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
                  if(@layout_mode == :square,
                    do: "bg-white text-blue-700 shadow-sm ring-1 ring-zinc-200",
                    else: "text-zinc-600 hover:bg-white/70 hover:text-zinc-900"
                  )
                ]}
                title="Show square cropped thumbnails"
              >
                <.icon name="hero-squares-2x2" class="w-4 h-4" />
                <span>Square</span>
              </button>
              <button
                type="button"
                phx-click="set-layout"
                phx-value-layout="masonry"
                data-media-layout="masonry"
                aria-pressed={
                  if(@layout_mode == :masonry, do: "true", else: "false")
                }
                class={[
                  "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
                  if(@layout_mode == :masonry,
                    do: "bg-white text-blue-700 shadow-sm ring-1 ring-zinc-200",
                    else: "text-zinc-600 hover:bg-white/70 hover:text-zinc-900"
                  )
                ]}
                title="Show images in natural proportions"
              >
                <.icon name="hero-view-columns" class="w-4 h-4" />
                <span>Masonry</span>
              </button>
            </div>

            <.button phx-click={JS.patch(~p"/admin/media/upload")}>
              <.icon name="hero-photo" class="w-5 h-5 -mt-0.5" />
              <span class="ms-1">
                New Image
              </span>
            </.button>
          </div>
        </div>

        <div :if={@media_count > 0} class="w-full pb-4">
          <.admin_search_bar
            id="media-search-form"
            input_id="media-search-input"
            name="search"
            value={@search_query}
            placeholder="Search by filename, title, or alt text..."
            debounce="300"
            on_change="search"
            clear_event="clear-search"
          />
        </div>

        <%!-- Drag and Drop Overlay --%>
        <div
          :if={@live_action != :upload}
          id="media-drop-zone"
          data-drop-zone-overlay
          phx-drop-target={@uploads.media_drop_uploads.ref}
          class={[
            "fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/20 backdrop-blur-[2px]",
            !@pending_upload_submit? && "hidden"
          ]}
        >
          <div class="mx-4 w-full max-w-sm rounded-xl border border-zinc-200 bg-white/95 p-6 text-center shadow-xl ring-1 ring-zinc-950/5">
            <div class="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-blue-50 text-blue-600 ring-1 ring-blue-100">
              <.icon name="hero-cloud-arrow-up" class="h-7 w-7" />
            </div>
            <p class="text-base font-semibold text-zinc-900">
              {if @pending_upload_submit?,
                do: "Uploading images",
                else: "Drop images to upload"}
            </p>
            <p class="mt-1 text-sm text-zinc-600">
              {if @pending_upload_submit?,
                do: "Keep this page open while the upload finishes.",
                else:
                  "Release anywhere on this page to add them to the media library."}
            </p>
            <div
              :if={@pending_upload_submit?}
              class="mt-5 overflow-hidden rounded-full bg-zinc-100 ring-1 ring-zinc-200"
            >
              <div
                class="h-2 rounded-full bg-blue-600 transition-all duration-300"
                style={"width: #{upload_progress(@uploads.media_drop_uploads.entries)}%"}
              >
              </div>
            </div>
            <div class="mt-3 rounded-lg border border-dashed border-zinc-300 bg-zinc-50 px-4 py-3 text-xs font-medium text-zinc-500">
              <%= if @pending_upload_submit? do %>
                {upload_progress(@uploads.media_drop_uploads.entries)}% uploaded
              <% else %>
                JPG, PNG, GIF, or WebP
              <% end %>
            </div>
          </div>
        </div>

        <section id="media-section" class="py-6 relative">
          <div
            :if={@media_count > 0}
            id="media-gallery"
            phx-hook="ScrollPreserver"
            class="pr-12"
          >
            <%= if @stream_initialized? do %>
              {render_images_by_year(assigns)}
            <% else %>
              <div
                id="media-gallery-loading"
                class="flex justify-center py-16"
                role="status"
                aria-live="polite"
              >
                <div class="flex flex-col items-center gap-3 text-zinc-500">
                  <.icon name="hero-arrow-path" class="w-10 h-10 animate-spin" />
                  <p class="text-sm font-medium">Loading images…</p>
                </div>
              </div>
            <% end %>
          </div>
          <%!-- Year Scrubber --%>
          <div
            :if={@media_count > 0 and length(@timeline) > 1}
            id="year-scrubber"
            phx-hook="YearScrubber"
            class="fixed right-4 top-1/2 -translate-y-1/2 z-50 flex flex-col items-center gap-1 py-2 px-1.5 bg-white/95 backdrop-blur-sm rounded-lg shadow-lg border border-zinc-200 transition-all duration-200 hover:shadow-xl"
          >
            <%!-- All / reset button --%>
            <button
              phx-click="show-all-years"
              class={[
                "w-9 h-9 flex items-center justify-center rounded transition-all duration-150 relative group",
                if(is_nil(@selected_year),
                  do: "bg-zinc-800 text-white opacity-100",
                  else:
                    "text-zinc-500 hover:text-zinc-900 hover:bg-zinc-100 opacity-60 hover:opacity-100"
                )
              ]}
              title="Show all years"
            >
              <.icon name="hero-squares-2x2" class="w-4 h-4" />
              <span class="absolute right-full top-1/2 -translate-y-1/2 mr-2 hidden group-hover:block bg-black text-white text-xs px-2 py-1 rounded whitespace-nowrap pointer-events-none">
                All years
              </span>
            </button>
            <div class="w-5 h-px bg-zinc-200 my-0.5"></div>
            <%= for item <- @timeline do %>
              <button
                data-year-item={item.year}
                phx-click="jump-to-year"
                phx-value-year={item.year}
                class="w-9 h-9 flex items-center justify-center text-xs font-semibold text-zinc-600 hover:text-zinc-900 rounded transition-all duration-150 opacity-60 hover:opacity-100 relative group"
                title={"#{item.year} (#{item.count} images)"}
              >
                <span class="group-hover:hidden flex items-center justify-center w-full h-full">
                  {String.slice(to_string(item.year), -2, 2)}
                </span>
                <span class="hidden group-hover:flex absolute inset-0 items-center justify-center text-xs font-bold whitespace-nowrap px-1">
                  {item.year}
                </span>
                <span class="absolute right-full top-1/2 -translate-y-1/2 mr-2 hidden group-hover:block bg-black text-white text-xs px-2 py-1 rounded whitespace-nowrap pointer-events-none">
                  {item.count} photos
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
              <.button phx-click={JS.patch(~p"/admin/media/upload")}>
                <.icon name="hero-cloud-arrow-up" class="w-5 h-5 -mt-0.5" />
                <span class="ms-1">
                  Upload Image
                </span>
              </.button>
            </div>
          </div>
        </section>
      </div>
    </.side_menu>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Media.subscribe_images()

    socket =
      socket
      |> assign(:media_count, 0)
      |> assign(:page_title, "Media")
      |> assign(:active_page, :media)
      |> assign(:timeline, [])
      |> assign(:available_years, [])
      |> assign(:timeline_loaded?, false)
      |> assign(:selected_year, nil)
      |> assign(:search_query, "")
      |> assign(:per_page, 30)
      |> assign(:end_of_timeline?, false)
      |> assign(:loading_more?, false)
      |> assign(:stream_initialized?, false)
      |> assign(:last_image_date, nil)
      |> assign(:last_image_id, nil)
      |> assign(:images_empty?, true)
      |> assign(:years_set, MapSet.new())
      |> assign(:years_list, [])
      |> assign(:uploaded_files, [])
      |> assign(:active_image, nil)
      |> assign(:image_uploader, nil)
      |> assign(:selected_image_version, :optimized)
      |> assign(:layout_mode, :masonry)
      |> assign(:show_drop_zone, false)
      |> assign(:pending_upload_submit?, false)
      |> assign(:sections, [])
      |> assign(form: nil)
      |> stream(:images, [], dom_id: &get_dom_id/1)
      |> allow_upload(:media_uploads,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 10,
        external: &presign_upload/2,
        progress: &handle_media_upload_progress/3
      )
      |> allow_upload(:media_drop_uploads,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 10,
        auto_upload: true,
        external: &presign_upload/2,
        progress: &handle_media_upload_progress/3
      )

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_params(params, uri, socket) do
    require Ysc.Logging

    Ysc.Logging.debug(
      "handle_params called with params: #{inspect(params)}, uri: #{inspect(uri)}"
    )

    # Load edit-modal data when opening an image — no remount needed.
    socket =
      case socket.assigns.live_action do
        :edit ->
          if connected?(socket) do
            image = Media.fetch_image(params["id"])
            image_uploader = Ysc.Accounts.get_user!(image.user_id)

            form =
              to_form(Media.Image.edit_image_changeset(image, %{}), as: "image")

            socket
            |> assign(:active_image, image)
            |> assign(:image_uploader, image_uploader)
            |> assign(:selected_image_version, :optimized)
            |> assign(form: form)
          else
            socket
          end

        _ ->
          socket
      end

    # Parse query parameters from URI to get year and search params
    query_params = parse_query_params_from_uri(params, uri)
    year_param = query_params["year"] || query_params[:year]
    search_query = query_params["search"] || query_params[:search] || ""
    previous_search_query = socket.assigns.search_query

    # Store current URL parameters in assigns for use when building return URLs
    socket =
      socket
      |> assign(:url_year_param, year_param)
      |> assign(:search_query, search_query)

    Ysc.Logging.debug(
      "Year param: #{inspect(year_param)}, Search query: #{inspect(search_query)}"
    )

    # Load timeline totals and gallery only after the WebSocket connects so the
    # first HTML response avoids database work.
    socket =
      if connected?(socket) do
        socket
        |> ensure_timeline_loaded()
        |> load_media_gallery_for_params(
          year_param,
          search_query,
          previous_search_query
        )
      else
        socket
      end

    {:noreply, socket}
  end

  defp ensure_timeline_loaded(%{assigns: %{timeline_loaded?: true}} = socket),
    do: socket

  defp ensure_timeline_loaded(socket) do
    timeline = Media.get_timeline_indices()
    media_count = Media.total_image_count_from_timeline(timeline)
    available_years = Enum.map(timeline, & &1.year)

    socket
    |> assign(:timeline, timeline)
    |> assign(:available_years, available_years)
    |> assign(:media_count, media_count)
    |> assign(:images_empty?, media_count == 0)
    |> assign(:timeline_loaded?, true)
  end

  defp load_media_gallery_for_params(
         socket,
         year_param,
         search_query,
         previous_search_query
       ) do
    require Ysc.Logging

    if year_param do
      year =
        if is_binary(year_param),
          do: String.to_integer(year_param),
          else: year_param

      Ysc.Logging.debug(
        "Processing year: #{year}, current: #{socket.assigns.selected_year}"
      )

      year_changed = year != socket.assigns.selected_year
      search_changed = search_query != previous_search_query
      not_initialized = not socket.assigns.stream_initialized?

      if year_changed || search_changed || not_initialized do
        start_date =
          DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC")

        end_date =
          DateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59], "Etc/UTC")

        images =
          Repo.all(
            year_images_query(
              start_date,
              end_date,
              search_query,
              socket.assigns.per_page
            )
          )

        Ysc.Logging.debug("Loaded #{length(images)} images for year #{year}")

        {years_set, years_list} = years_from_images(images)
        stream_items = Timeline.inject_sections(images)

        socket
        |> assign(:selected_year, year)
        |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
        |> assign(:stream_initialized?, true)
        |> assign_cursor_from_images(images)
        |> assign(:images_empty?, images == [])
        |> assign(:years_set, years_set)
        |> assign(:years_list, years_list)
        |> reset_image_sections(stream_items)
      else
        socket
      end
    else
      has_year_filter = not is_nil(socket.assigns.selected_year)
      search_changed = search_query != previous_search_query
      not_initialized = not socket.assigns.stream_initialized?

      if has_year_filter || search_changed || not_initialized do
        images =
          Media.list_images_cursor(
            limit: socket.assigns.per_page,
            search: search_query
          )

        {years_set, years_list} = years_from_images(images)
        stream_items = Timeline.inject_sections(images)

        socket
        |> assign(:selected_year, nil)
        |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
        |> assign(:stream_initialized?, true)
        |> assign_cursor_from_images(images)
        |> assign(:images_empty?, images == [])
        |> assign(:years_set, years_set)
        |> assign(:years_list, years_list)
        |> reset_image_sections(stream_items)
      else
        socket
      end
    end
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
    if upload_entries_in_progress?(socket, :media_uploads) do
      {:noreply, assign(socket, :pending_upload_submit?, true)}
    else
      {:noreply, save_uploaded_media(socket, :media_uploads)}
    end
  end

  def handle_event("drop-upload-started", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_drop_zone, false)
     |> assign(:pending_upload_submit?, true)}
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

    timeline = Media.get_timeline_indices()
    available_years = Enum.map(timeline, & &1.year)
    images = Media.list_images_cursor(limit: socket.assigns.per_page)
    {years_set, years_list} = years_from_images(images)
    stream_items = Timeline.inject_sections(images)

    {:noreply,
     socket
     |> assign(:timeline, timeline)
     |> assign(:available_years, available_years)
     |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
     |> assign(:stream_initialized?, true)
     |> assign_cursor_from_images(images)
     |> assign(:images_empty?, images == [])
     |> assign(:years_set, years_set)
     |> assign(:years_list, years_list)
     |> reset_image_sections(stream_items)
     |> push_patch(to: build_media_url_with_state(socket))}
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
    stream_items = Timeline.inject_sections(images)

    new_years =
      Enum.map(images, fn image -> image.inserted_at.year end) |> MapSet.new()

    years_list = new_years |> MapSet.to_list() |> Enum.sort(:desc)

    {:noreply,
     socket
     |> assign(:selected_year, nil)
     |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
     |> assign(:images_empty?, images == [])
     |> assign_cursor_from_images(images)
     |> assign(:years_set, new_years)
     |> assign(:years_list, years_list)
     |> reset_image_sections(stream_items)}
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

    stream_items = Timeline.inject_sections(images)

    new_years =
      Enum.map(images, fn image -> image.inserted_at.year end) |> MapSet.new()

    years_list = new_years |> MapSet.to_list() |> Enum.sort(:desc)

    {:noreply,
     socket
     |> assign(:selected_year, year)
     |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
     |> assign(:images_empty?, images == [])
     |> assign_cursor_from_images(images)
     |> assign(:years_set, new_years)
     |> assign(:years_list, years_list)
     |> reset_image_sections(stream_items)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    require Ysc.Logging

    last_image_date = socket.assigns.last_image_date
    last_image_id = socket.assigns.last_image_id
    search_query = socket.assigns.search_query

    if socket.assigns.end_of_timeline? or is_nil(last_image_date) or
         socket.assigns[:loading_more?] do
      {:noreply, socket}
    else
      before_cursor = {last_image_date, last_image_id}

      socket = assign(socket, :loading_more?, true)

      new_images =
        if socket.assigns.selected_year do
          year = socket.assigns.selected_year

          start_date =
            DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC")

          end_date =
            DateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59], "Etc/UTC")

          Repo.all(
            year_images_query(
              start_date,
              end_date,
              search_query,
              socket.assigns.per_page,
              before_cursor
            )
          )
        else
          Media.list_images_cursor(
            before_date: last_image_date,
            before_id: last_image_id,
            limit: socket.assigns.per_page,
            search: search_query
          )
        end

      Ysc.Logging.debug("Load-more: loaded #{length(new_images)} images")

      case new_images do
        [] ->
          {:noreply,
           socket
           |> assign(:end_of_timeline?, true)
           |> assign(:loading_more?, false)}

        [_ | _] ->
          first_new_image_date = List.first(new_images).inserted_at

          needs_header =
            last_image_date.year != first_new_image_date.year ||
              last_image_date.month != first_new_image_date.month

          {new_years_set, _} = years_from_images(new_images)
          updated_years = MapSet.union(socket.assigns.years_set, new_years_set)
          years_list = updated_years |> MapSet.to_list() |> Enum.sort(:desc)

          socket =
            socket
            |> assign(
              :end_of_timeline?,
              length(new_images) < socket.assigns.per_page
            )
            |> assign_cursor_from_images(new_images)
            |> assign(:years_set, updated_years)
            |> assign(:years_list, years_list)

          socket =
            if needs_header do
              new_sections = Timeline.inject_sections(new_images)

              socket
              |> assign(:sections, socket.assigns.sections ++ new_sections)
              |> stream(:images, new_sections, at: -1, dom_id: &get_dom_id/1)
            else
              old_len = length(socket.assigns.sections)

              updated_sections =
                Timeline.append_images_to_last_section(
                  socket.assigns.sections,
                  new_images
                )

              stream_items =
                if length(updated_sections) > old_len do
                  Enum.drop(updated_sections, old_len - 1)
                else
                  [List.last(updated_sections)]
                end

              socket
              |> assign(:sections, updated_sections)
              |> stream(:images, stream_items, dom_id: &get_dom_id/1)
            end

          {:noreply, assign(socket, :loading_more?, false)}
      end
    end
  end

  def handle_event("show-all-years", _params, socket) do
    images =
      Media.list_images_cursor(
        limit: socket.assigns.per_page,
        search: socket.assigns.search_query
      )

    {years_set, years_list} = years_from_images(images)
    stream_items = Timeline.inject_sections(images)

    socket =
      socket
      |> assign(:selected_year, nil)
      |> assign(:url_year_param, nil)
      |> assign(:years_set, years_set)
      |> assign(:years_list, years_list)
      |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
      |> assign(:stream_initialized?, true)
      |> assign_cursor_from_images(images)
      |> assign(:images_empty?, images == [])
      |> reset_image_sections(stream_items)
      |> push_patch(to: ~p"/admin/media")

    {:noreply, socket}
  end

  def handle_event("jump-to-year", %{"year" => year}, socket) do
    year_int = if is_binary(year), do: String.to_integer(year), else: year

    # Jump within the full timeline — do not set a year filter so load-more
    # can continue into older years seamlessly.
    images =
      Media.list_images_cursor(
        start_at_year: year_int,
        limit: socket.assigns.per_page,
        search: socket.assigns.search_query
      )

    {years_set, years_list} = years_from_images(images)
    stream_items = Timeline.inject_sections(images)

    socket =
      socket
      |> assign(:selected_year, nil)
      |> assign(:url_year_param, nil)
      |> assign(:years_set, years_set)
      |> assign(:years_list, years_list)
      |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
      |> assign(:stream_initialized?, true)
      |> assign_cursor_from_images(images)
      |> assign(:images_empty?, images == [])
      |> reset_image_sections(stream_items)
      |> push_event("scroll-to-year", %{year: year_int})

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => search_query}, socket) do
    search_query = String.trim(search_query)

    new_params =
      if search_query == "" do
        %{}
      else
        %{"search" => search_query}
      end

    # Preserve year filter if present
    new_params =
      if socket.assigns.selected_year do
        Map.put(new_params, "year", to_string(socket.assigns.selected_year))
      else
        new_params
      end

    {:noreply, push_patch(socket, to: ~p"/admin/media?#{new_params}")}
  end

  def handle_event("clear-search", %{"input-id" => _input_id}, socket) do
    new_params =
      if socket.assigns.selected_year do
        %{"year" => to_string(socket.assigns.selected_year)}
      else
        %{}
      end

    {:noreply, push_patch(socket, to: ~p"/admin/media?#{new_params}")}
  end

  def handle_event("set-layout", %{"layout" => layout}, socket) do
    layout_mode =
      case layout do
        "masonry" -> :masonry
        _ -> :square
      end

    {:noreply,
     socket
     |> assign(:layout_mode, layout_mode)
     |> stream(:images, socket.assigns.sections,
       reset: true,
       dom_id: &get_dom_id/1
     )}
  end

  def handle_event("show-drop-zone", _params, socket) do
    {:noreply, assign(socket, :show_drop_zone, true)}
  end

  def handle_event("hide-drop-zone", _params, socket) do
    {:noreply, assign(socket, :show_drop_zone, false)}
  end

  @impl true
  def handle_info({Media, {:image_updated, image_id}}, socket) do
    case Media.fetch_image(image_id) do
      nil ->
        {:noreply, socket}

      image ->
        socket =
          if socket.assigns.active_image &&
               socket.assigns.active_image.id == image.id do
            assign(socket, :active_image, image)
          else
            socket
          end

        case update_image_in_sections(socket.assigns.sections, image) do
          {updated_sections, changed_sections} ->
            {:noreply,
             socket
             |> assign(:sections, updated_sections)
             |> stream(:images, changed_sections, dom_id: &get_dom_id/1)}

          nil ->
            {:noreply, socket}
        end
    end
  end

  defp handle_media_upload_progress(:media_uploads, _entry, socket) do
    if socket.assigns.pending_upload_submit? and
         upload_entries_done?(socket, :media_uploads) do
      {:noreply, save_uploaded_media(socket, :media_uploads)}
    else
      {:noreply, socket}
    end
  end

  defp handle_media_upload_progress(:media_drop_uploads, _entry, socket) do
    if upload_entries_done?(socket, :media_drop_uploads) do
      {:noreply, save_uploaded_media(socket, :media_drop_uploads)}
    else
      {:noreply, socket}
    end
  end

  defp save_uploaded_media(socket, upload_name) do
    uploader = socket.assigns[:current_user]

    uploaded_files =
      consume_uploaded_entries(socket, upload_name, fn details, _entry ->
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

    timeline = Media.get_timeline_indices()
    media_count = Media.total_image_count_from_timeline(timeline)
    available_years = Enum.map(timeline, & &1.year)
    images = Media.list_images_cursor(limit: socket.assigns.per_page)
    {years_set, years_list} = years_from_images(images)
    stream_items = Timeline.inject_sections(images)

    socket
    |> update(:uploaded_files, &(&1 ++ uploaded_files))
    |> assign(:media_count, media_count)
    |> assign(:timeline, timeline)
    |> assign(:available_years, available_years)
    |> assign(:end_of_timeline?, length(images) < socket.assigns.per_page)
    |> assign(:stream_initialized?, true)
    |> assign_cursor_from_images(images)
    |> assign(:images_empty?, images == [])
    |> assign(:years_set, years_set)
    |> assign(:years_list, years_list)
    |> assign(:show_drop_zone, false)
    |> assign(:pending_upload_submit?, false)
    |> reset_image_sections(stream_items)
    |> push_patch(to: ~p"/admin/media")
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
        expires_in: :timer.hours(1),
        server_side_encryption: S3Config.server_side_encryption?()
      )

    upload_url = S3Config.upload_url()
    :ok = S3Config.assert_direct_upload_url!(upload_url, :media)

    meta = %{
      uploader: "S3",
      key: key,
      url: upload_url,
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

  defp upload_entries_in_progress?(socket, upload_name) do
    socket.assigns.uploads[upload_name].entries
    |> Enum.any?(&(not &1.done?))
  end

  defp upload_entries_done?(socket, upload_name) do
    entries = socket.assigns.uploads[upload_name].entries
    entries != [] and Enum.all?(entries, & &1.done?)
  end

  defp upload_progress([]), do: 0

  defp upload_progress(entries) do
    entries
    |> Enum.map(& &1.progress)
    |> Enum.sum()
    |> div(length(entries))
  end

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
  defp get_image_path(%Media.Image{thumbnail_path: nil} = image),
    do: image.raw_image_path

  defp get_image_path(%Media.Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp get_image_path(%Media.Image{thumbnail_path: thumbnail_path}),
    do: thumbnail_path

  # Get DOM ID for stream items (year-month sections)
  defp get_dom_id(%Timeline.Section{id: id}), do: id

  defp reset_image_sections(socket, sections) do
    socket
    |> assign(:sections, sections)
    |> stream(:images, sections, reset: true, dom_id: &get_dom_id/1)
  end

  defp update_image_in_sections(sections, %Media.Image{id: image_id} = image) do
    case Enum.find_index(sections, fn section ->
           Enum.any?(section.images, &(&1.id == image_id))
         end) do
      nil ->
        nil

      index ->
        section = Enum.at(sections, index)

        updated_images =
          Enum.map(section.images, fn
            %{id: ^image_id} -> image
            other -> other
          end)

        updated_section = %{section | images: updated_images}
        updated_sections = List.replace_at(sections, index, updated_section)
        {updated_sections, [updated_section]}
    end
  end

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

    search_query = assigns[:search_query] || ""

    query_params = []

    query_params =
      if year, do: [{"year", year} | query_params], else: query_params

    query_params =
      if search_query != "",
        do: [{"search", search_query} | query_params],
        else: query_params

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

    search_query = assigns[:search_query] || ""

    query_params = []

    query_params =
      if year, do: [{"year", year} | query_params], else: query_params

    query_params =
      if search_query != "",
        do: [{"search", search_query} | query_params],
        else: query_params

    base_path = ~p"/admin/media/upload/#{image_id}"

    if Enum.any?(query_params) do
      query_string = URI.encode_query(query_params)
      "#{base_path}?#{query_string}"
    else
      base_path
    end
  end

  defp years_from_images(images) do
    years_set =
      images
      |> Enum.map(& &1.inserted_at.year)
      |> MapSet.new()

    years_list = years_set |> MapSet.to_list() |> Enum.sort(:desc)
    {years_set, years_list}
  end

  defp year_images_query(
         start_date,
         end_date,
         search_query,
         limit,
         before_cursor \\ nil
       ) do
    query =
      from i in Media.Image,
        where: i.inserted_at >= ^start_date and i.inserted_at <= ^end_date,
        order_by: [desc: i.inserted_at, desc: i.id],
        limit: ^limit

    query =
      case before_cursor do
        {before_date, before_id} when not is_nil(before_id) ->
          from i in query,
            where:
              i.inserted_at < ^before_date or
                (i.inserted_at == ^before_date and i.id < ^before_id)

        before_date when not is_nil(before_date) ->
          from i in query, where: i.inserted_at < ^before_date

        nil ->
          query
      end

    apply_image_search(query, search_query)
  end

  defp apply_image_search(query, search_query)
       when is_binary(search_query) and search_query != "" do
    search_pattern = "%#{search_query}%"

    from i in query,
      where:
        ilike(i.title, ^search_pattern) or
          ilike(i.alt_text, ^search_pattern) or
          ilike(
            fragment(
              "regexp_replace(?, '.*/([^/]+)$', '\\1')",
              i.raw_image_path
            ),
            ^search_pattern
          )
  end

  defp apply_image_search(query, _search_query), do: query

  defp copy_alt_text(%Media.Image{} = image) do
    image.alt_text || image.title || "Image"
  end

  defp html_alt_text(%Media.Image{} = image) do
    image
    |> copy_alt_text()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp markdown_alt_text(%Media.Image{} = image) do
    image
    |> copy_alt_text()
    |> String.replace("\\", "\\\\")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end

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

  defp positive_image_dimension(value) when is_integer(value) and value > 0,
    do: value

  defp positive_image_dimension(_), do: nil

  defp render_images_by_year(assigns) do
    ~H"""
    <%!-- Empty Search State --%>
    <%= if @search_query != "" && @images_empty? do %>
      <div class="mx-auto py-20 text-center">
        <div class="flex flex-col items-center">
          <.icon name="hero-magnifying-glass" class="w-16 h-16 text-zinc-300 mb-4" />
          <p class="text-lg font-medium text-zinc-700 mb-2">No results found</p>
          <p class="text-sm text-zinc-500 mb-6">
            No images match "{@search_query}"
          </p>
          <button
            phx-click="clear-search"
            phx-value-input-id="media-search-input"
            class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-zinc-700 bg-white border border-zinc-300 rounded hover:bg-zinc-50 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" /> Clear search
          </button>
        </div>
      </div>
    <% else %>
      <div
        id="media-scroll-container"
        phx-hook="MediaGalleryInfiniteScroll"
        data-load-more-enabled={to_string(!@end_of_timeline? && !@loading_more?)}
      >
        <div
          id="images-grid"
          phx-update="stream"
          class="pb-10"
        >
          <%= for {id, %Timeline.Section{} = section} <- @streams.images do %>
            <div
              id={id}
              class="media-year-section"
              data-year-section={section.header.date.year}
            >
              <div class="sticky top-0 z-10 bg-white/95 backdrop-blur py-4 px-4 mt-4 font-bold text-xl border-b border-zinc-200">
                {section.header.formatted_date}
              </div>
              <div class={
                if(@layout_mode == :square,
                  do:
                    "media-square-grid grid gap-3 md:gap-4 grid-cols-2 md:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 3xl:grid-cols-7 4xl:grid-cols-9",
                  else: "media-masonry-grid"
                )
              }>
                <%= for item <- section.images do %>
                  <button
                    phx-click={
                      JS.patch(build_image_edit_url_with_state(assigns, item.id))
                    }
                    id={"image-#{item.id}"}
                    class={[
                      "group relative w-full rounded-lg border border-zinc-200 cursor-pointer hover:border-blue-500 hover:ring-2 hover:ring-blue-500 hover:ring-offset-2 hover:shadow-lg focus:outline-none focus-visible:border-blue-500 focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2 focus-visible:shadow-lg transition-all duration-200 overflow-hidden",
                      if(@layout_mode == :square,
                        do: "aspect-square",
                        else: "media-masonry-card bg-zinc-100"
                      )
                    ]}
                  >
                    <%!-- Processing Overlay --%>
                    <%= if item.processing_state != :completed do %>
                      <div class="absolute inset-0 z-10 bg-black/50 flex items-center justify-center">
                        <div class="text-center">
                          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-white mx-auto mb-2">
                          </div>
                          <p class="text-xs font-medium text-white">
                            Processing...
                          </p>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Missing Alt Text Warning --%>
                    <%= if is_nil(item.alt_text) || item.alt_text == "" do %>
                      <div
                        class="absolute top-2 right-2 z-[3] flex h-7 w-7 items-center justify-center rounded-full bg-yellow-500 text-white shadow-lg"
                        title="Missing alt text"
                        aria-label="Missing alt text"
                      >
                        <.icon
                          name="hero-exclamation-triangle"
                          class="h-4 w-4 flex-none"
                        />
                      </div>
                    <% end %>

                    <canvas
                      id={"blur-hash-img-#{item.id}"}
                      src={Media.Image.blur_hash_for_display(item)}
                      class="absolute inset-0 z-0 h-full w-full rounded-lg object-cover"
                      phx-hook="BlurHashCanvas"
                    ></canvas>

                    <img
                      class={[
                        "z-[1] rounded-lg opacity-0 transition-opacity duration-300 ease-out group-hover:opacity-100",
                        if(@layout_mode == :square,
                          do: "absolute inset-0 h-full w-full object-cover",
                          else: "relative block h-auto w-full object-contain"
                        )
                      ]}
                      id={"img-#{item.id}"}
                      src={get_image_path(item)}
                      width={positive_image_dimension(item.width)}
                      height={positive_image_dimension(item.height)}
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
                        {item.title}
                      </p>
                      <p
                        :if={item.title == nil and item.alt_text != nil}
                        class="text-xs font-medium text-white/90 truncate"
                        title={item.alt_text}
                      >
                        {item.alt_text}
                      </p>
                    </div>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
        <div
          :if={!@end_of_timeline?}
          id="media-load-more-footer"
          class="flex flex-col items-center justify-center gap-2 border-t border-zinc-100 py-10 text-zinc-500"
          aria-live="polite"
        >
          <%= if @loading_more? do %>
            <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin" />
            <p class="text-sm font-medium">Loading more images…</p>
          <% else %>
            <.icon name="hero-chevron-down" class="h-5 w-5 animate-bounce" />
            <p class="text-sm font-medium">Scroll down for more images</p>
          <% end %>
        </div>
        <div
          :if={@stream_initialized? && !@images_empty? && @end_of_timeline?}
          id="media-end-of-library"
          class="flex flex-col items-center justify-center gap-1 border-t border-zinc-100 py-10 text-zinc-400"
        >
          <.icon name="hero-check-circle" class="h-5 w-5" />
          <p class="text-sm font-medium">End of the media library</p>
        </div>
      </div>
    <% end %>
    """
  end
end
