defmodule YscWeb.AdminPostEditorLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Posts.Post
  alias Ysc.Posts
  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  @save_debounce_timeout 2000

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
        :if={@live_action == :preview}
        show={true}
        fullscreen={true}
        id="admin-post-preview-modal"
        on_cancel={JS.navigate(~p"/admin/posts/#{@post_id}")}
      >
        <div class="flex flex-col h-[86vh]">
          <ul class="flex flex-wrap items-center justify-center pb-4">
            <li>
              <button
                type="button"
                class={[
                  "flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3",
                  @preview_device == :phone && "bg-zinc-100"
                ]}
                phx-click="phone-preview"
              >
                <.icon name="hero-device-phone-mobile" class="w-8 h-8" />
                <span class="sr-only">Phone preview</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                class={[
                  "flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3",
                  @preview_device == :tablet && "bg-zinc-100"
                ]}
                phx-click="tablet-preview"
              >
                <.icon name="hero-device-tablet" class="w-8 h-8 " />
                <span class="sr-only">Tablet preview</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                class={[
                  "flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3",
                  @preview_device == :computer && "bg-zinc-100"
                ]}
                phx-click="computer-preview"
              >
                <.icon name="hero-computer-desktop" class="w-8 h-8 " />
                <span class="sr-only">Desktop preview</span>
              </button>
            </li>
          </ul>

          <div class={[
            "w-full bg-blue-100 h-full rounded border border-1 border-zinc-300",
            (@preview_device == :phone || @preview_device == :tablet) && "py-20"
          ]}>
            <.phone_mockup :if={@preview_device == :phone} class="m-auto">
              <iframe
                src={"/posts/#{@post_id}"}
                class={[
                  "h-full w-full"
                ]}
              >
              </iframe>
            </.phone_mockup>

            <.tablet_mockup :if={@preview_device == :tablet} class="m-auto">
              <iframe
                src={"/posts/#{@post_id}"}
                class={[
                  "h-full w-full"
                ]}
              >
              </iframe>
            </.tablet_mockup>

            <iframe
              :if={@preview_device == :computer}
              src={"/posts/#{@post_id}"}
              class={[
                "h-full w-full"
              ]}
            >
            </iframe>
          </div>
        </div>
      </.modal>

      <.modal
        :if={@live_action == :settings}
        show={true}
        fullscreen={false}
        id="admin-post-settings-modal"
        on_cancel={JS.navigate(~p"/admin/posts/#{@post_id}")}
      >
        <div class="flex flex-col">
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
            Post Settings
          </h2>

          <div class="rounded border border-1 border-zinc-100 px-3 py-4">
            <p class="text-lg font-semibold mb-3">Featured Image</p>

            <div class="flex flex-col gap-3">
              <div
                :if={@post.image_id && @post.featured_image}
                class="flex items-center gap-3"
              >
                <img
                  src={
                    @post.featured_image.thumbnail_path ||
                      @post.featured_image.optimized_image_path ||
                      @post.featured_image.raw_image_path
                  }
                  class="w-64 object-cover rounded border border-1 border-zinc-200"
                  alt={@post.featured_image.alt_text}
                  loading="lazy"
                />
              </div>

              <div :if={!@post.image_id} class="text-sm text-red-600">
                No featured image set.
              </div>

              <div class="mt-4">
                <p class="text-xs text-zinc-500 mb-2">Choose from recent images</p>
                <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-2">
                  <%= for image <- @featured_image_choices do %>
                    <button
                      type="button"
                      class="group relative w-full rounded aspect-video border border-1 border-zinc-200 cursor-pointer hover:border-zinc-300"
                      phx-click="set-featured-image"
                      phx-value-id={image.id}
                    >
                      <img
                        class="w-full h-full rounded object-cover group-hover:opacity-80 transition-opacity duration-75 ease-in-out"
                        src={
                          image.thumbnail_path || image.optimized_image_path ||
                            image.raw_image_path
                        }
                        alt={image.alt_text}
                        loading="lazy"
                      />
                    </button>
                  <% end %>
                </div>

                <div class="flex justify-between items-center mt-3">
                  <.button
                    :if={!@featured_images_start?}
                    phx-click="prev-featured-images"
                    phx-disable-with="Loading..."
                  >
                    Previous
                  </.button>
                  <span class="flex-1"></span>
                  <.button
                    :if={!@featured_images_end?}
                    phx-click="next-featured-images"
                    phx-disable-with="Loading..."
                  >
                    Next
                  </.button>
                </div>
              </div>

              <div class="mt-4">
                <p class="text-xs text-zinc-500 mb-2">Or upload a new image</p>
                <form
                  id="featured-upload-form"
                  phx-submit="save-featured-upload"
                  phx-change="validate-featured-upload"
                >
                  <label
                    class="flex p-4 flex-col items-center justify-center w-full min-h-40 border-2 border-zinc-300 border-dashed rounded-lg cursor-pointer bg-zinc-50 hover:bg-zinc-100"
                    phx-drop-target={@uploads.featured_image_upload.ref}
                  >
                    <.live_file_input
                      upload={@uploads.featured_image_upload}
                      class="hidden"
                    />

                    <div class="flex flex-row flex-wrap gap-2">
                      <%= for entry <- @uploads.featured_image_upload.entries do %>
                        <article class="upload-entry">
                          <figure class="w-28 group relative">
                            <button
                              type="button"
                              phx-click="cancel-featured-upload"
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
                              <figcaption class="text-xs truncate overflow-hidden bg-zinc-100 text-zinc-600 w-28 z-8 absolute inset-x-0 bottom-0 py-1">
                                <%= entry.client_name %>
                              </figcaption>
                            </button>
                          </figure>

                          <%= for err <- upload_errors(@uploads.featured_image_upload, entry) do %>
                            <p class="text-xs text-red-600 font-semibold mt-1">
                              <.icon
                                name="hero-exclamation-circle"
                                class="-mt-0.5 h-4 w-4"
                              /> <%= error_to_string(err) %>
                            </p>
                          <% end %>
                        </article>
                      <% end %>
                    </div>

                    <%= for err <- upload_errors(@uploads.featured_image_upload) do %>
                      <p class="text-xs text-red-600 font-semibold mt-1">
                        <.icon
                          name="hero-exclamation-circle"
                          class="-mt-0.5 h-4 w-4"
                        /> <%= error_to_string(err) %>
                      </p>
                    <% end %>

                    <div
                      :if={length(@uploads.featured_image_upload.entries) == 0}
                      class="flex flex-col items-center justify-center pt-2 pb-3"
                    >
                      <.icon
                        name="hero-cloud-arrow-up"
                        class="w-8 h-10 mb-2 text-zinc-500"
                      />
                      <p class="mb-1 text-sm text-zinc-500">
                        <span class="font-semibold">Click to upload</span>
                        or drag and drop
                      </p>
                      <p class="text-xs text-zinc-500">
                        SVG, PNG, JPG, JPEG or GIF
                      </p>
                    </div>
                  </label>

                  <div class="w-full flex justify-end pt-3">
                    <.button
                      type="submit"
                      phx-disable-with="Uploading..."
                      aria-disabled={
                        length(@uploads.featured_image_upload.entries) == 0
                      }
                      disabled={length(@uploads.featured_image_upload.entries) == 0}
                    >
                      Upload and set as featured
                    </.button>
                  </div>
                </form>
              </div>
            </div>
          </div>
        </div>
      </.modal>

      <.form
        :let={_f}
        for={@form}
        id="edit_post_form"
        phx-submit="save"
        phx-change="post-update"
      >
        <div class="w-full flex flex-row justify-between">
          <div class="w-full flex flex-row items-center align-middle mt-4">
            <.input
              type="text-growing"
              field={@form[:title]}
              phx-debounce="500"
              growing_field_size="large"
              class="input-element mt-2 block w-full font-extrabold text-3xl outline-none border-none focus:border focus:border-1 focus:border-zinc-200 rounded text-zinc-900 focus:border-1 focus:border-zinc-400 focus:outline focus:outline-zinc-200 focus:ring-0 leading-6 focus:border-zinc-400"
            />

            <.badge type={post_state_to_badge_style(@post.state)} class="mt-3 ml-3">
              <%= String.capitalize("#{@post.state}") %>
            </.badge>

            <p class={"text-sm text-zinc-600 transition duration-200 ease-in-out align-middle inline-block items-center px-1 mt-4 #{if @saving? == true, do: "opacity-100", else: "opacity-0"}"}>
              <span>
                <.icon
                  name="hero-arrow-path"
                  class="w-4 h-4 -mt-0.5 animate-spin mr-1"
                />
              </span>
              Saving...
            </p>
          </div>

          <div class="flex flex-row align-baseline items-end">
            <.button
              :if={@post.state == :draft}
              class="hidden lg:block w-28 mr-3"
              type="button"
              phx-click="publish-post"
            >
              <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-1" />
              <span class="me-1">Publish</span>
            </.button>

            <.button
              :if={@post.state == :deleted}
              color="green"
              class="hidden lg:block w-28 mr-3"
              type="button"
              phx-click="restore-post"
            >
              <.icon name="hero-cloud-arrow-up" class="w-5 h-5 -mt-1" />
              <span class="me-1">Restore</span>
            </.button>

            <button
              type="button"
              class="hidden lg:block flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3"
              phx-click={JS.navigate(~p"/admin/posts/#{@post_id}/preview")}
            >
              <.icon name="hero-computer-desktop" class="w-5 h-5 -mt-1" />
              <span class="sr-only">Preview post</span>
            </button>

            <.dropdown
              id="edit-post-more"
              right={true}
              class="text-zinc-800 hover:bg-zinc-100 hover:text-black"
            >
              <:button_block>
                <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
              </:button_block>

              <div class="w-full divide-y divide-zinc-100 text-sm text-zinc-700">
                <ul class="block lg:hidden py-2">
                  <li>
                    <.link
                      navigate={~p"/admin/posts/#{@post_id}/preview"}
                      class="block px-4 py-2 transition ease-in-out hover:bg-zinc-100 duration-400"
                    >
                      <.icon
                        name="hero-document-arrow-up"
                        class="w-5 h-5 -mt-1 mr-1"
                      />
                      <span>Publish</span>
                    </.link>
                  </li>
                  <li>
                    <.link
                      navigate={~p"/admin/posts/#{@post_id}/preview"}
                      class="block px-4 py-2 transition ease-in-out hover:bg-zinc-100 duration-400"
                    >
                      <.icon
                        name="hero-computer-desktop"
                        class="w-5 h-5 -mt-1 mr-1"
                      />
                      <span>Preview</span>
                    </.link>
                  </li>
                </ul>

                <ul class="py-2 text-sm font-medium text-zinc-800 py-1">
                  <li>
                    <li>
                      <.link
                        navigate={~p"/admin/posts/#{@post_id}/settings"}
                        class="block px-4 py-2 transition ease-in-out hover:bg-zinc-100 duration-400"
                      >
                        <.icon
                          name="hero-adjustments-horizontal"
                          class="w-5 h-5 -mt-1 mr-1"
                        />
                        <span>Post Settings</span>
                      </.link>
                    </li>
                  </li>

                  <li class="block py-2 px-3 transition text-red-600 ease-in-out duration-200 hover:bg-zinc-100">
                    <button
                      type="button"
                      class="w-full text-left px-1"
                      phx-click="delete-post"
                    >
                      <.icon name="hero-trash" class="w-5 h-5 -mt-1" />
                      <span>Delete Post</span>
                    </button>
                  </li>
                </ul>
              </div>
            </.dropdown>
          </div>
        </div>

        <div class="text-sm text-zinc-500 leading-6 py-1 flex flex-row align-baseline items-end">
          <span>
            <.link navigate={~p"/posts/#{@post.url_name}"} target="_blank">
              <.icon
                name="hero-arrow-top-right-on-square"
                class=" text-zinc-800 w-4 h-4 -mt-1 mr-2"
              />
            </.link>
          </span>
          <span class="pt-2 mr-1 hidden lg:block">
            <%= "#{YscWeb.Endpoint.url()}/posts/" %>
          </span>
          <span>
            <.input
              type="text-growing"
              field={@form[:url_name]}
              class="input-element mt-2 block w-full text-sm outline-none border-none focus:border focus:border-1 focus:border-zinc-200 rounded text-blue-600 focus:border-1 focus:border-zinc-400 focus:outline focus:outline-zinc-200 focus:ring-0 leading-6 focus:border-zinc-400"
            />
          </span>
        </div>
      </.form>

      <.form :let={_f} for={@form} id="trix-editor-form">
        <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none mx-auto py-8">
          <.input
            type="hidden"
            id="post[raw_body]"
            field={@form[:raw_body]}
            data-post-id={@post_id}
            phx-hook="TrixHook"
          />
          <div id="richtext" phx-update="ignore">
            <trix-editor
              input="post[raw_body]"
              class="trix-content block mt-8 max-w-2xl mx-auto px-8 py-8 bg-white border-0 focus:ring-0 text-wrap"
              placeholder="Write something delightful and nice..."
            >
            </trix-editor>
          </div>
        </div>
      </.form>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    post = Posts.get_post!(id) |> Ysc.Repo.preload(:featured_image)
    update_post_changeset = Post.update_post_changeset(post, %{})

    YscWeb.Endpoint.subscribe("post_saved:#{id}")

    {:ok,
     socket
     |> assign(:page_title, post.title)
     |> assign(:active_page, :news)
     |> assign(:saving?, false)
     |> assign(:post_id, post.id)
     |> assign(:post, post)
     |> assign(:featured_image_choices, [])
     |> assign(:featured_images_page, 1)
     |> assign(:featured_images_per_page, 10)
     |> assign(:featured_images_end?, false)
     |> assign(:featured_images_start?, true)
     |> assign(:preview_device, :computer)
     |> assign(form: to_form(update_post_changeset, as: "post"))
     |> allow_upload(:featured_image_upload,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       external: &presign_upload/2
     )}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      case socket.assigns[:live_action] do
        :settings -> load_featured_image_choices(socket, 1)
        _ -> socket
      end

    {:noreply, socket}
  end

  @spec handle_event(<<_::32, _::_*8>>, any(), atom() | map()) ::
          {:noreply, map()}
  def handle_event("post-update", %{"post" => values}, socket) do
    post = socket.assigns[:post]

    # Ensure UI is not cleared out
    updated_values =
      Map.put_new(values, "title", post.title)
      |> Map.put_new("url_name", post.url_name)

    changeset = Post.update_post_changeset(%Post{}, updated_values)
    form_socket = assign_form(socket, Map.put(changeset, :action, :validate))

    # Don't save too often. We wait a little and only save once user has stopped
    # typing or removes focus from the field. Even if user navigates away from the page
    # this function runs in a separate process and will complete.
    Debouncer.delay(
      socket.assigns[:post_id],
      fn ->
        # Only run DB validation if it has actually changed
        opts =
          if post.url_name != Map.get(values, "url_name", "") do
            [validate_url_name: true]
          else
            []
          end

        # Need to scrub if html body has changed
        html_scrubbed_values =
          if Map.has_key?(values, "raw_body") do
            Map.put(
              values,
              "rendered_body",
              Scrubber.scrub(Map.get(values, "raw_body"), Scrubber.BasicHTML)
            )
          else
            values
          end

        Posts.update_post(
          %Post{id: socket.assigns[:post_id]},
          html_scrubbed_values,
          socket.assigns[:current_user],
          opts
        )

        YscWeb.Endpoint.broadcast(
          "post_saved:#{socket.assigns[:post_id]}",
          "saved",
          socket.assigns[:post_id]
        )
      end,
      @save_debounce_timeout
    )

    {:noreply, form_socket |> assign(:saving?, true)}
  end

  def handle_event("save", %{"post" => _values} = req, socket) do
    handle_event("post-update", req, socket)
  end

  def handle_event("editor-update", params, socket) do
    handle_event("post-update", %{"post" => params}, socket)
  end

  def handle_event("publish-post", _params, socket) do
    post = socket.assigns[:post]

    if is_nil(post.image_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Please set a featured image before publishing.")
       |> push_navigate(to: ~p"/admin/posts/#{post.id}/settings")}
    else
      res =
        Posts.update_post(
          post,
          %{state: :published, published_on: Timex.now()},
          socket.assigns[:current_user]
        )

      case res do
        {:ok, new_post} ->
          {:noreply,
           socket
           |> assign(:post, new_post)
           |> put_flash(:info, "The post was published!")
           |> redirect(to: ~p"/admin/posts/#{post.id}")}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Something went wrong")
           |> redirect(to: ~p"/admin/posts")}
      end
    end
  end

  def handle_event("restore-post", _params, socket) do
    post = socket.assigns[:post]

    res =
      Posts.update_post(
        post,
        %{
          state: :draft,
          published_on: nil,
          deleted_on: nil,
          featured_post: false
        },
        socket.assigns[:current_user]
      )

    case res do
      {:ok, new_post} ->
        {:noreply,
         socket
         |> assign(:post, new_post)
         |> put_flash(:info, "The post recovered.")
         |> redirect(to: ~p"/admin/posts/#{post.id}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Something went wrong")
         |> redirect(to: ~p"/admin/posts")}
    end
  end

  def handle_event("delete-post", _params, socket) do
    post = socket.assigns[:post]

    res =
      Posts.update_post(
        post,
        %{
          state: :deleted,
          deleted_on: Timex.now(),
          published_on: nil,
          featured_post: false
        },
        socket.assigns[:current_user]
      )

    case res do
      {:ok, new_post} ->
        {:noreply,
         socket
         |> assign(:post, new_post)
         |> put_flash(:info, "The post was deleted.")
         |> redirect(to: ~p"/admin/posts")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Something went wrong")
         |> redirect(to: ~p"/admin/posts")}
    end
  end

  def handle_event("phone-preview", _params, socket) do
    {:noreply, assign(socket, :preview_device, :phone)}
  end

  def handle_event("tablet-preview", _params, socket) do
    {:noreply, assign(socket, :preview_device, :tablet)}
  end

  def handle_event("computer-preview", _params, socket) do
    {:noreply, assign(socket, :preview_device, :computer)}
  end

  def handle_event("set-featured-image", %{"id" => image_id}, socket) do
    post_id = socket.assigns[:post_id]
    current_user = socket.assigns[:current_user]

    case Posts.update_post(
           %Post{id: post_id},
           %{"image_id" => image_id},
           current_user
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           :post,
           Posts.get_post!(post_id) |> Ysc.Repo.preload(:featured_image)
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not set featured image")}
    end
  end

  def handle_event("unset-featured-image", _params, socket) do
    post_id = socket.assigns[:post_id]
    current_user = socket.assigns[:current_user]

    case Posts.update_post(
           %Post{id: post_id},
           %{"image_id" => nil},
           current_user
         ) do
      {:ok, _} ->
        {:noreply,
         assign(
           socket,
           :post,
           Posts.get_post!(post_id) |> Ysc.Repo.preload(:featured_image)
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not remove featured image")}
    end
  end

  def handle_event("next-featured-images", _params, socket) do
    {:noreply,
     load_featured_image_choices(
       socket,
       socket.assigns[:featured_images_page] + 1
     )}
  end

  def handle_event("prev-featured-images", _params, socket) do
    new_page = max(1, socket.assigns[:featured_images_page] - 1)
    {:noreply, load_featured_image_choices(socket, new_page)}
  end

  def handle_event("validate-featured-upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-featured-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :featured_image_upload, ref)}
  end

  def handle_event("save-featured-upload", _params, socket) do
    uploader = socket.assigns[:current_user]
    post_id = socket.assigns[:post_id]

    uploaded_files =
      consume_uploaded_entries(socket, :featured_image_upload, fn details,
                                                                  _entry ->
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
      case uploaded_files do
        [new_image | _] ->
          case Posts.update_post(
                 %Post{id: post_id},
                 %{"image_id" => new_image.id},
                 uploader
               ) do
            {:ok, _} ->
              assign(
                socket,
                :post,
                Posts.get_post!(post_id) |> Ysc.Repo.preload(:featured_image)
              )

            {:error, _} ->
              put_flash(socket, :error, "Could not set featured image")
          end

        _ ->
          socket
      end

    {:noreply, updated_socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "saved"}, socket) do
    {:noreply,
     assign(socket, :saving?, false)
     |> assign(
       :post,
       Posts.get_post!(socket.assigns[:post_id])
       |> Ysc.Repo.preload(:featured_image)
     )}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "post")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp load_featured_image_choices(socket, page) do
    per_page = socket.assigns[:featured_images_per_page]
    images = Media.list_images((page - 1) * per_page, per_page)

    socket
    |> assign(:featured_image_choices, images)
    |> assign(:featured_images_page, page)
    |> assign(:featured_images_start?, page <= 1)
    |> assign(:featured_images_end?, length(images) < per_page)
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

  defp post_state_to_badge_style(:draft), do: "yellow"
  defp post_state_to_badge_style(:published), do: "green"
  defp post_state_to_badge_style(:deleted), do: "red"
  defp post_state_to_badge_style(_), do: "default"
end
