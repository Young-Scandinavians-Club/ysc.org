defmodule YscWeb.AdminPostEditorLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Media.Image
  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Posts.Slug

  @save_debounce_timeout 2000
  @new_post_debounce_key "new_post"

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <.modal
        :if={@live_action == :preview}
        show={true}
        fullscreen={true}
        id="admin-post-preview-modal"
        on_cancel={JS.patch(~p"/admin/posts/#{@post_id}")}
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
              ></iframe>
            </.phone_mockup>

            <.tablet_mockup :if={@preview_device == :tablet} class="m-auto">
              <iframe
                src={"/posts/#{@post_id}"}
                class={[
                  "h-full w-full"
                ]}
              ></iframe>
            </.tablet_mockup>

            <iframe
              :if={@preview_device == :computer}
              src={"/posts/#{@post_id}"}
              class={[
                "h-full w-full"
              ]}
            ></iframe>
          </div>
        </div>
      </.modal>

      <.modal
        :if={@live_action == :settings}
        show={true}
        fullscreen={false}
        id="admin-post-settings-modal"
        on_cancel={JS.patch(~p"/admin/posts/#{@post_id}")}
      >
        <div class="flex flex-col">
          <.admin_page_title level={2} class="mb-4">
            Post Settings
          </.admin_page_title>

          <div class="rounded border border-1 border-zinc-100 px-3 py-4">
            <p class="text-lg font-semibold mb-3">Featured Image</p>

            <.live_component
              module={YscWeb.MediaPickerComponent}
              id={:post_featured_image}
              user_id={@current_user.id}
              image_id={@post.image_id}
            />
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
        <div class="mt-4 flex w-full items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <div class="inline-flex max-w-full min-w-0 flex-wrap items-center gap-x-3 gap-y-2">
              <div class="flex min-w-0 w-max max-w-full items-center">
                <.input
                  type="text-growing"
                  field={@form[:title]}
                  phx-debounce="500"
                  growing_field_size="large"
                  class="input-element block border-none font-extrabold text-2xl leading-7 text-zinc-900 outline-none focus:border focus:border-1 focus:border-zinc-200 focus:border-zinc-400 focus:outline focus:outline-zinc-200 focus:ring-0 sm:text-3xl sm:leading-8 rounded"
                />
              </div>

              <.badge
                type={post_state_to_badge_style(@post.state)}
                class="shrink-0 self-center"
              >
                {String.capitalize("#{@post.state}")}
              </.badge>

              <.admin_help_link
                topic="posts/publish"
                label="Publishing help"
                role={@admin_role}
                class="self-center"
              />

              <p class={[
                "inline-flex shrink-0 items-center text-sm text-zinc-600 transition duration-200 ease-in-out",
                @saving? && "opacity-100",
                !@saving? && "opacity-0"
              ]}>
                <.icon
                  name="hero-arrow-path"
                  class="mr-1 h-4 w-4 shrink-0 animate-spin"
                /> Saving...
              </p>
            </div>
          </div>

          <div class="flex shrink-0 flex-row items-center gap-2 pt-0.5">
            <.button
              :if={@post.state == :draft}
              class="hidden lg:mr-1 lg:inline-flex lg:w-28"
              type="button"
              phx-click="publish-post"
            >
              <.icon name="hero-document-arrow-up" class="h-5 w-5 shrink-0" />
              <span>Publish</span>
            </.button>

            <.button
              :if={@post.state == :deleted}
              color="green"
              class="hidden lg:mr-1 lg:inline-flex lg:w-28"
              type="button"
              phx-click="restore-post"
            >
              <.icon name="hero-cloud-arrow-up" class="h-5 w-5 shrink-0" />
              <span>Restore</span>
            </.button>

            <.button
              :if={@post_id}
              id="post-editor-preview-patch"
              patch={~p"/admin/posts/#{@post_id}/preview"}
              variant="outline"
              color="zinc"
              class="hidden flex-none lg:mr-1 lg:inline-flex px-3 py-2 text-zinc-800 transition duration-200 ease-in-out hover:bg-zinc-100"
            >
              <.icon name="hero-computer-desktop" class="h-5 w-5 shrink-0" />
              <span class="sr-only">Preview post</span>
            </.button>

            <.dropdown
              id="edit-post-more"
              right={true}
              class="text-zinc-800 hover:bg-zinc-100 hover:text-black"
            >
              <:button_block>
                <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
              </:button_block>

              <div class="w-full divide-y divide-zinc-100 text-sm text-zinc-700">
                <ul class="py-2 lg:hidden">
                  <li :if={@post.state == :draft}>
                    <button
                      id={"publish-post-#{@post_id || "new"}"}
                      type="button"
                      class="flex w-full items-center gap-2 px-4 py-2 text-left transition duration-300 ease-in-out hover:bg-zinc-100"
                      phx-click="publish-post"
                    >
                      <.icon
                        name="hero-document-arrow-up"
                        class="h-5 w-5 shrink-0 text-zinc-500"
                      />
                      <span>Publish</span>
                    </button>
                  </li>
                  <li :if={@post.state == :deleted}>
                    <button
                      id={"restore-post-#{@post_id || "new"}"}
                      type="button"
                      class="flex w-full items-center gap-2 px-4 py-2 text-left text-green-700 transition duration-300 ease-in-out hover:bg-zinc-100"
                      phx-click="restore-post"
                      disabled={@unsaved?}
                    >
                      <.icon
                        name="hero-cloud-arrow-up"
                        class="h-5 w-5 shrink-0"
                      />
                      <span>Restore</span>
                    </button>
                  </li>
                  <li :if={@post_id}>
                    <.link
                      id={"preview-post-#{@post_id}"}
                      navigate={~p"/admin/posts/#{@post_id}/preview"}
                      class="flex w-full items-center gap-2 px-4 py-2 text-left transition duration-300 ease-in-out hover:bg-zinc-100"
                    >
                      <.icon
                        name="hero-computer-desktop"
                        class="h-5 w-5 shrink-0 text-zinc-500"
                      />
                      <span>Preview</span>
                    </.link>
                  </li>
                </ul>

                <ul class="py-2 text-sm font-medium text-zinc-800">
                  <li>
                    <button
                      :if={@unsaved?}
                      id="settings-post-new"
                      type="button"
                      class="block w-full px-4 py-2 text-left transition duration-300 ease-in-out hover:bg-zinc-100"
                      phx-click="open-settings"
                    >
                      <.icon
                        name="hero-adjustments-horizontal"
                        class="mr-2 h-5 w-5 -mt-1"
                      />
                      <span>Post Settings</span>
                    </button>
                    <.link
                      :if={@post_id && !@unsaved?}
                      id={"settings-post-#{@post_id}"}
                      navigate={~p"/admin/posts/#{@post_id}/settings"}
                      class="block px-4 py-2 transition duration-300 ease-in-out hover:bg-zinc-100"
                    >
                      <.icon
                        name="hero-adjustments-horizontal"
                        class="mr-2 h-5 w-5 -mt-1"
                      />
                      <span>Post Settings</span>
                    </.link>
                  </li>

                  <li
                    :if={@post_id}
                    class="px-3 py-2 text-red-600 transition duration-200 ease-in-out hover:bg-zinc-100"
                  >
                    <button
                      id={"delete-post-#{@post_id}"}
                      type="button"
                      class="w-full px-1 text-left"
                      phx-click="delete-post"
                    >
                      <.icon name="hero-trash" class="inline h-5 w-5 -mt-1" />
                      <span>Delete Post</span>
                    </button>
                  </li>
                </ul>
              </div>
            </.dropdown>
          </div>
        </div>

        <div class="flex flex-col gap-1 py-1 text-sm leading-6 text-zinc-500 sm:flex-row sm:items-end sm:gap-2">
          <span :if={@post_id && @post.url_name}>
            <.link
              navigate={~p"/posts/#{@post.url_name}"}
              target="_blank"
              rel="noopener noreferrer"
            >
              <.icon
                name="hero-arrow-top-right-on-square"
                class=" text-zinc-800 w-4 h-4 -mt-1 mr-2"
              />
            </.link>
          </span>
          <span
            :if={!@post_id || !@post.url_name}
            class="text-zinc-400"
            title="Save the post to preview the public URL"
          >
            <.icon
              name="hero-arrow-top-right-on-square"
              class="w-4 h-4 -mt-1 mr-2 text-zinc-300"
            />
          </span>
          <span class="pt-2 mr-1 hidden lg:block">
            {"#{YscWeb.Endpoint.url()}/posts/"}
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
          <.live_component
            module={YscWeb.TrixImagePickerComponent}
            id={:post_body_image_picker}
            target_input_id="post[raw_body]"
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

  def mount(_params, _session, %{assigns: %{live_action: :new}} = socket) do
    create_topic = "post_editor:#{socket.id}"
    YscWeb.Endpoint.subscribe(create_topic)

    default_title = Slug.default_title()

    changeset =
      Post.editor_changeset(%Post{state: :draft}, %{
        "title" => default_title,
        "url_name" => Slug.from_title(default_title)
      })

    {:ok,
     socket
     |> assign(:create_topic, create_topic)
     |> assign(:page_title, default_title)
     |> assign(:active_page, :news)
     |> assign(:saving?, false)
     |> assign(:unsaved?, true)
     |> assign(:auto_url_name?, true)
     |> assign(:pending_publish?, false)
     |> assign(:pending_form_values, %{
       "title" => default_title,
       "url_name" => Slug.from_title(default_title)
     })
     |> assign(:post_id, nil)
     |> assign(:post, %Post{
       state: :draft,
       title: default_title,
       url_name: Slug.from_title(default_title)
     })
     |> assign(:preview_device, :computer)
     |> assign(form: to_form(changeset, as: "post"))}
  end

  def mount(%{"id" => id}, _session, socket) do
    post = Posts.get_post!(id) |> Ysc.Repo.preload(:featured_image)

    form_attrs =
      if Slug.blank_title?(post.title) do
        default_title = Slug.default_title()

        %{
          "title" => default_title,
          "url_name" => post.url_name || Slug.from_title(default_title)
        }
      else
        %{}
      end

    update_post_changeset = Post.editor_changeset(post, form_attrs)

    YscWeb.Endpoint.subscribe("post_saved:#{id}")

    {:ok,
     socket
     |> assign(:page_title, post.title)
     |> assign(:active_page, :news)
     |> assign(:saving?, false)
     |> assign(:unsaved?, false)
     |> assign(:auto_url_name?, false)
     |> assign(:pending_publish?, false)
     |> assign(:pending_form_values, %{})
     |> assign(:create_topic, nil)
     |> assign(:post_id, post.id)
     |> assign(:post, post)
     |> assign(:preview_device, :computer)
     |> assign(form: to_form(update_post_changeset, as: "post"))}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      if socket.assigns.live_action != :settings do
        assign(socket, :pending_publish?, false)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("post-update", %{"post" => values}, socket) do
    post = socket.assigns.post

    updated_values =
      values
      |> Map.put_new("title", post.title || Slug.default_title())
      |> Map.put_new("url_name", post.url_name || "")

    {updated_values, title_restored?} = ensure_title_present(updated_values)

    socket =
      if title_restored? do
        assign(socket, :auto_url_name?, true)
      else
        socket
      end

    {updated_values, auto_url_name?} =
      maybe_sync_url_name(socket, updated_values)

    changeset =
      Post.editor_changeset(%Post{}, updated_values)
      |> Map.put(:action, :validate)

    form_socket =
      socket
      |> assign(:auto_url_name?, auto_url_name?)
      |> assign(:pending_form_values, updated_values)
      |> assign_form(changeset)

    unsaved? = socket.assigns.unsaved?
    post_id = socket.assigns.post_id
    current_user = socket.assigns.current_user
    previous_url_name = post.url_name
    create_topic = socket.assigns[:create_topic]

    debounce_key = post_id || @new_post_debounce_key

    Debouncer.delay(
      debounce_key,
      fn ->
        html_scrubbed_values = scrub_raw_body(updated_values)

        if unsaved? do
          params =
            html_scrubbed_values
            |> Map.put("state", "draft")
            |> ensure_url_name_for_persist()

          case Posts.create_post(params, current_user) do
            {:ok, new_post} ->
              YscWeb.Endpoint.broadcast(create_topic, "created", new_post.id)

            {:error, reason} ->
              YscWeb.Endpoint.broadcast(
                create_topic,
                "create_failed",
                %{reason: reason}
              )
          end
        else
          opts =
            if previous_url_name != Map.get(updated_values, "url_name", "") do
              [validate_url_name: true]
            else
              []
            end

          persist_values =
            html_scrubbed_values
            |> maybe_unique_url_name(previous_url_name, updated_values)

          case Posts.update_post_editor(
                 %Post{id: post_id},
                 persist_values,
                 current_user,
                 opts
               ) do
            {:ok, _} ->
              YscWeb.Endpoint.broadcast(
                "post_saved:#{post_id}",
                "saved",
                post_id
              )

            {:error, reason} ->
              YscWeb.Endpoint.broadcast(
                "post_saved:#{post_id}",
                "save_failed",
                %{post_id: post_id, reason: reason}
              )
          end
        end
      end,
      @save_debounce_timeout
    )

    {:noreply, form_socket |> assign(:saving?, true)}
  end

  def handle_event("save", %{"post" => _values} = req, socket) do
    handle_event("post-update", req, socket)
  end

  def handle_event(
        "editor-update",
        %{"field" => _field, "value" => value},
        socket
      ) do
    handle_event("post-update", %{"post" => %{"raw_body" => value}}, socket)
  end

  def handle_event("open-settings", _params, socket) do
    case ensure_persisted(socket) do
      {:ok, socket} ->
        {:noreply,
         push_patch(socket,
           to: ~p"/admin/posts/#{socket.assigns.post_id}/settings"
         )}

      {:error, socket} ->
        {:noreply, persist_error_toast(socket)}
    end
  end

  def handle_event("publish-post", _params, socket) do
    case ensure_persisted(socket) do
      {:error, socket} ->
        {:noreply, persist_error_toast(socket)}

      {:ok, socket} ->
        post = socket.assigns.post

        if is_nil(post.image_id) do
          {:noreply,
           socket
           |> assign(:pending_publish?, true)
           |> push_patch(to: ~p"/admin/posts/#{post.id}/settings")}
        else
          case publish_post(socket) do
            {:ok, socket} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(:info, "Post published!",
                 title: "Published"
               )
               |> redirect(to: ~p"/admin/posts/#{post.id}")}

            {:error, socket} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "Something went wrong. Please try again.",
                 title: "Publish failed"
               )
               |> redirect(to: ~p"/admin/posts")}
          end
        end
    end
  end

  def handle_event("restore-post", _params, socket) do
    post = socket.assigns.post

    res =
      Posts.update_post(
        post,
        %{
          state: :draft,
          published_on: nil,
          deleted_on: nil,
          featured_post: false
        },
        socket.assigns.current_user
      )

    case res do
      {:ok, new_post} ->
        {:noreply,
         socket
         |> assign(:post, new_post)
         |> YscWeb.Flash.put_toast(:info, "Post restored.",
           title: "Post restored"
         )
         |> redirect(to: ~p"/admin/posts/#{post.id}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Something went wrong. Please try again.",
           title: "Restore failed"
         )
         |> redirect(to: ~p"/admin/posts")}
    end
  end

  def handle_event("delete-post", _params, socket) do
    post = socket.assigns.post

    res =
      Posts.update_post(
        post,
        %{
          state: :deleted,
          deleted_on: Timex.now(),
          published_on: nil,
          featured_post: false
        },
        socket.assigns.current_user
      )

    case res do
      {:ok, new_post} ->
        {:noreply,
         socket
         |> assign(:post, new_post)
         |> YscWeb.Flash.put_toast(:info, "Post deleted.",
           title: "Post deleted"
         )
         |> redirect(to: ~p"/admin/posts")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Something went wrong. Please try again.",
           title: "Delete failed"
         )
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

  def handle_info({YscWeb.MediaPickerComponent, _id, :cleared}, socket) do
    post_id = socket.assigns.post_id
    current_user = socket.assigns.current_user

    case Posts.update_post_editor(
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

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Could not remove featured image.",
           title: "Featured image"
         )}
    end
  end

  def handle_info({YscWeb.MediaPickerComponent, _id, image_id}, socket)
      when is_binary(image_id) do
    post_id = socket.assigns.post_id
    current_user = socket.assigns.current_user

    case Posts.update_post_editor(
           %Post{id: post_id},
           %{"image_id" => image_id},
           current_user
         ) do
      {:ok, _} ->
        post = Posts.get_post!(post_id) |> Ysc.Repo.preload(:featured_image)

        socket =
          socket
          |> assign(:post, post)
          |> maybe_complete_pending_publish()

        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Could not set featured image.",
           title: "Featured image"
         )}
    end
  end

  def handle_info({YscWeb.TrixImagePickerComponent, _id, image}, socket) do
    url = Image.display_path(image)

    {:noreply,
     push_event(socket, "insert-trix-image", %{
       url: url,
       href: "#{url}?content-disposition=attachment",
       alt: image.alt_text || image.title || "",
       target_input_id: "post[raw_body]"
     })}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "created", payload: post_id},
        socket
      ) do
    post = Posts.get_post!(post_id) |> Ysc.Repo.preload(:featured_image)
    YscWeb.Endpoint.subscribe("post_saved:#{post_id}")

    {:noreply,
     socket
     |> assign(:saving?, false)
     |> assign(:unsaved?, false)
     |> assign(:post_id, post_id)
     |> assign(:post, post)
     |> assign(:page_title, post.title)
     |> push_patch(to: ~p"/admin/posts/#{post_id}", replace: true)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "saved"}, socket) do
    {:noreply,
     assign(socket, :saving?, false)
     |> assign(
       :post,
       Posts.get_post!(socket.assigns.post_id)
       |> Ysc.Repo.preload(:featured_image)
     )}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "create_failed"}, socket) do
    {:noreply,
     socket
     |> assign(:saving?, false)
     |> persist_error_toast()}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "save_failed"}, socket) do
    {:noreply,
     socket
     |> assign(:saving?, false)
     |> persist_error_toast()}
  end

  defp ensure_title_present(values) do
    title = Map.get(values, "title")

    if Slug.blank_title?(title) do
      {Map.put(values, "title", Slug.default_title()), true}
    else
      {values, false}
    end
  end

  defp maybe_sync_url_name(socket, values) do
    title = values |> Map.get("title") |> Slug.title_or_default()
    auto_slug = Slug.from_title(title)

    values =
      if socket.assigns.auto_url_name? do
        Map.put(values, "url_name", auto_slug)
      else
        values
      end

    auto_url_name? = Map.get(values, "url_name", "") == auto_slug

    {values, auto_url_name?}
  end

  defp ensure_persisted(socket) do
    if socket.assigns.unsaved? do
      {values, _} = ensure_title_present(socket.assigns.pending_form_values)

      case create_post_from_values(values, socket.assigns.current_user) do
        {:ok, post} ->
          YscWeb.Endpoint.subscribe("post_saved:#{post.id}")

          {:ok,
           socket
           |> assign(:unsaved?, false)
           |> assign(:post_id, post.id)
           |> assign(:post, post)
           |> assign(:page_title, post.title)}

        {:error, _} ->
          {:error, socket}
      end
    else
      {:ok, socket}
    end
  end

  defp create_post_from_values(values, current_user) do
    values
    |> scrub_raw_body()
    |> Map.put("state", "draft")
    |> ensure_url_name_for_persist()
    |> then(&Posts.create_post(&1, current_user))
    |> case do
      {:ok, post} ->
        {:ok, Posts.get_post!(post.id) |> Ysc.Repo.preload(:featured_image)}

      error ->
        error
    end
  end

  defp ensure_url_name_for_persist(params) do
    params =
      Map.update(
        params,
        "title",
        Slug.default_title(),
        &Slug.title_or_default/1
      )

    url_name =
      params
      |> Map.get("url_name")
      |> case do
        nil -> Slug.from_title(params["title"])
        "" -> Slug.from_title(params["title"])
        name -> name
      end
      |> Slug.unique()

    Map.put(params, "url_name", url_name)
  end

  defp maybe_unique_url_name(params, previous_url_name, updated_values) do
    new_url_name = Map.get(updated_values, "url_name", "")

    if previous_url_name != new_url_name do
      Map.put(params, "url_name", Slug.unique(new_url_name))
    else
      params
    end
  end

  defp scrub_raw_body(values) do
    if Map.has_key?(values, "raw_body") do
      Map.put(
        values,
        "rendered_body",
        Scrubber.scrub(Map.get(values, "raw_body"), Scrubber.BasicHTML)
      )
    else
      values
    end
  end

  defp publish_post(socket) do
    post = socket.assigns.post

    case Posts.update_post(
           post,
           %{state: :published, published_on: Timex.now()},
           socket.assigns.current_user
         ) do
      {:ok, new_post} ->
        {:ok, assign(socket, :post, new_post)}

      {:error, _changeset} ->
        {:error, socket}
    end
  end

  defp maybe_complete_pending_publish(socket) do
    if socket.assigns.pending_publish? do
      case publish_post(socket) do
        {:ok, socket} ->
          socket
          |> assign(:pending_publish?, false)
          |> YscWeb.Flash.put_toast(:info, "Post published!",
            title: "Published"
          )
          |> push_patch(to: ~p"/admin/posts/#{socket.assigns.post_id}")

        {:error, socket} ->
          socket
          |> assign(:pending_publish?, false)
          |> YscWeb.Flash.put_toast(
            :error,
            "Something went wrong. Please try again.",
            title: "Publish failed"
          )
      end
    else
      socket
    end
  end

  defp persist_error_toast(socket) do
    YscWeb.Flash.put_toast(
      socket,
      :error,
      "Could not save the post. Please try again.",
      title: "Save failed"
    )
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "post")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp post_state_to_badge_style(:draft), do: "yellow"
  defp post_state_to_badge_style(:published), do: "green"
  defp post_state_to_badge_style(:deleted), do: "red"
  defp post_state_to_badge_style(_), do: "default"
end
