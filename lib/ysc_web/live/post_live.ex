defmodule YscWeb.PostLive do
  alias Ysc.Media.Image
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Posts.Comment

  @board_position_to_title_lookup %{
    president: "President",
    vice_president: "Vice President",
    secretary: "Secretary",
    treasurer: "Treasurer",
    clear_lake_cabin_master: "Clear Lake Cabin Master",
    tahoe_cabin_master: "Tahoe Cabin Master",
    event_director: "Event Director",
    member_outreach: "Member Outreach & Events",
    membership_director: "Membership Director"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Reading Progress Bar --%>
    <div
      id="reading-progress-container"
      class="fixed top-0 left-0 w-full h-1 z-50 pointer-events-none"
      phx-hook="ReadingProgress"
    >
      <div
        id="reading-progress"
        class="h-full bg-teal-500 transition-all duration-150"
        style="width: 0%"
      >
      </div>
    </div>

    <div class="py-8 lg:py-10">
      <div :if={@post == nil} class="my-14 mx-auto">
        <.empty_viking_state
          viking={4}
          title="Sorry! The article could not be located"
          suggestion="Please check the link you came from and try again."
        />
      </div>

      <%!-- The "Journalist" Header Section --%>
      <div :if={@post != nil} class="max-w-screen-lg mx-auto px-4">
        <div class="max-w-3xl mx-auto text-center mb-12">
          <div class="flex items-center justify-center gap-3 mb-6">
            <span class="text-[10px] font-black text-teal-600 uppercase tracking-[0.3em]">
              Club News
            </span>
            <span class="h-3 w-px bg-zinc-200"></span>
            <span class="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">
              <%= Timex.format!(post_date(@post), "{Mshort} {D}, {YYYY}") %>
            </span>
          </div>
          <h1 class="text-4xl md:text-6xl font-black text-zinc-900 tracking-tighter leading-[1.1] mb-8">
            <%= @post.title %>
          </h1>
          <div class="flex items-center justify-center gap-4 py-6 border-y border-zinc-100">
            <.user_avatar_image
              email={@post.author.email}
              user_id={@post.author.id}
              country={@post.author.most_connected_country}
              class="w-10 h-10 rounded-full"
            />
            <div class="text-left">
              <p class="text-[10px] font-black text-zinc-900 uppercase tracking-widest">
                Post By
              </p>
              <p class="text-sm font-medium text-zinc-500">
                <%= String.capitalize(@post.author.first_name || "") %>
                <%= String.capitalize(@post.author.last_name || "") %>
                <%= if @post.author.board_position do %>
                  , YSC <%= format_board_position(@post.author.board_position) %>
                <% end %>
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- The "Immersive" Hero Image --%>
      <div
        :if={@post != nil && @post.image_id != nil}
        id="post-featured-image"
        class="mt-16 md:mt-20 relative mx-auto rounded-xl max-w-6xl aspect-video overflow-hidden"
      >
        <canvas
          id={"blur-hash-image-#{@post.image_id}"}
          src={get_blur_hash(@post.featured_image)}
          class="absolute inset-0 z-0 w-full h-full object-cover"
          phx-hook="BlurHashCanvas"
        >
        </canvas>

        <img
          src={featured_image_url(@post.featured_image)}
          id={"image-#{@post.image_id}"}
          loading="lazy"
          class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out w-full h-full object-cover"
          phx-hook="BlurHashImage"
          alt={
            if @post.featured_image,
              do:
                @post.featured_image.alt_text || @post.featured_image.title ||
                  @post.title ||
                  "Featured image",
              else: "Featured image"
          }
        />
      </div>

      <%!-- Typography Palate Cleanser with Drop Cap --%>
      <div :if={@post != nil} class="max-w-screen-lg mx-auto px-4">
        <article class="prose prose-zinc prose-lg lg:prose-xl prose-a:text-teal-600 prose-strong:text-zinc-900 max-w-3xl mx-auto py-12 bg-zinc-50/50 rounded-xl px-8 md:px-12">
          <div
            id="article-body"
            class="post-render first-letter:text-7xl first-letter:font-black first-letter:text-zinc-900 first-letter:mr-3 first-letter:float-left first-letter:leading-[.8] leading-relaxed text-zinc-600 font-light border-l border-zinc-100 ml-[-2rem] pl-8"
            phx-hook="GLightboxHook"
          >
            <%= raw(@post.raw_body) %>
          </div>
        </article>
      </div>

      <%!-- Interactive "Discussion" Area --%>
      <div
        :if={@post != nil && @current_user != nil}
        class="max-w-screen-lg mx-auto px-4 mt-16"
      >
        <section class="max-w-2xl mx-auto">
          <div class="bg-white border border-zinc-200 rounded-xl p-10 shadow-sm">
            <div class="flex items-center gap-3 mb-8">
              <div class="w-1.5 h-6 bg-teal-500 rounded-full"></div>
              <h2 class="text-2xl font-black text-zinc-900 tracking-tight">
                Community Discussion (<%= @n_comments %>)
              </h2>
            </div>

            <.form
              class="group mb-6"
              for={@form}
              id="primary-post-comment"
              phx-submit="save"
            >
              <.input
                field={@form[:text]}
                type="textarea"
                id="comment"
                rows="4"
                class="w-full bg-zinc-50 border-none rounded-lg p-6 text-zinc-900 placeholder:text-zinc-400 focus:ring-2 focus:ring-teal-500/20 transition-all min-h-[120px]"
                placeholder="Share your thoughts..."
                required
              >
              </.input>
              <input type="hidden" name="comment[post_id]" value={@post.id} />
              <div class="flex justify-end mt-4">
                <.button type="submit" phx-disable-with="Posting...">
                  Post Comment
                  <.icon
                    :if={@loading}
                    name="hero-arrow-path"
                    class="w-4 h-4 animate-spin ml-2 text-white"
                  />
                </.button>
              </div>
            </.form>

            <%!-- Loading skeleton for comments --%>
            <div :if={!@comments_loaded && @n_comments > 0} class="space-y-4">
              <%= for _i <- 1..min(@n_comments, 3) do %>
                <div class="flex gap-4 p-4 bg-zinc-50 rounded-lg animate-pulse">
                  <div class="w-10 h-10 bg-zinc-200 rounded-full flex-shrink-0">
                  </div>
                  <div class="flex-1 space-y-2">
                    <div class="h-3 bg-zinc-200 rounded w-1/4"></div>
                    <div class="h-4 bg-zinc-200 rounded w-full"></div>
                    <div class="h-4 bg-zinc-200 rounded w-3/4"></div>
                  </div>
                </div>
              <% end %>
            </div>

            <div
              :if={@comments_loaded}
              id={"comment-section-#{@post.id}"}
              phx-update="stream"
            >
              <.comment
                :for={{id, comment} <- @streams.comments}
                id={id}
                text={comment.text}
                author={"#{String.capitalize(comment.author.first_name)} #{String.capitalize(comment.author.last_name)}"}
                author_email={comment.author.email}
                author_most_connected={comment.author.most_connected_country}
                author_id={comment.author.id}
                date={comment.inserted_at}
                form={@form}
                post_id={@post.id}
                reply_to_comment_id={get_reply_to_id(comment)}
                reply={comment_is_reply(comment)}
                animate={@animate_insert}
              />
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id} = _params, _session, socket) do
    # Load post synchronously - essential for SEO (title, content, image)
    post =
      case Ecto.ULID.cast(id) do
        {:ok, ulid_id} -> Posts.get_post(ulid_id, [:author, :featured_image])
        :error -> Posts.get_post_by_url_name(id, [:author, :featured_image])
      end

    case post do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Article not found")
         |> redirect(to: ~p"/news")}

      post ->
        # Essential assigns for initial render (SEO-critical)
        new_comment_changeset =
          Posts.Comment.new_comment_changeset(%Posts.Comment{}, %{})

        socket =
          socket
          |> assign(:post_id, id)
          |> assign(:post, post)
          |> assign(:page_title, post.title)
          |> assign(:animate_insert, false)
          # Use cached comment_count from post for initial render
          |> assign(:n_comments, post.comment_count)
          |> assign(:loading, false)
          |> assign(:comments_loaded, false)
          |> assign_form(new_comment_changeset)
          # Initialize empty stream for comments (will be populated after connection)
          |> stream(:comments, [])

        if connected?(socket) do
          # Subscribe to real-time updates only when connected
          YscWeb.Endpoint.subscribe(Posts.post_topic(post.id))

          # Load comments asynchronously (not needed for SEO)
          {:ok, load_comments_async(socket, post.id),
           temporary_assigns: [form: nil]}
        else
          {:ok, socket, temporary_assigns: [form: nil]}
        end
    end
  end

  # Load comments asynchronously after WebSocket connection
  defp load_comments_async(socket, post_id) do
    start_async(socket, :load_comments, fn ->
      comments = Posts.get_comments_for_post(post_id, [:author])
      Posts.sort_comments_for_render(comments)
    end)
  end

  @impl true
  def handle_async(:load_comments, {:ok, sorted_comments}, socket) do
    # Re-assign the form since temporary_assigns clears it after each render
    # The .comment component needs a valid form to render
    new_comment_changeset =
      Posts.Comment.new_comment_changeset(%Posts.Comment{}, %{})

    {:noreply,
     socket
     |> assign(:comments_loaded, true)
     |> assign_form(new_comment_changeset)
     |> stream(:comments, sorted_comments, reset: true)}
  end

  def handle_async(:load_comments, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load comments async: #{inspect(reason)}")
    # Still need to provide a form even on error
    new_comment_changeset =
      Posts.Comment.new_comment_changeset(%Posts.Comment{}, %{})

    {:noreply,
     socket
     |> assign(:comments_loaded, true)
     |> assign_form(new_comment_changeset)}
  end

  @impl true
  def handle_event("save", %{"comment" => comment}, socket) do
    text_body = Map.get(comment, "text", "")
    # Ensure no bad stuff gets rendered ever
    # It will be escaped later for safety but lets be defensive
    scrubbed_comment =
      Map.put(comment, "text", Scrubber.scrub(text_body, Scrubber.BasicHTML))

    current_user = socket.assigns[:current_user]

    Posts.add_comment_to_post(scrubbed_comment, current_user)

    {:noreply, socket |> assign(:loading, true)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "new_comment", payload: new_comment},
        socket
      ) do
    loaded = Posts.get_comment!(new_comment.id, [:author])

    new_comment_changeset =
      Posts.Comment.new_comment_changeset(%Posts.Comment{}, %{})

    new_socket =
      socket
      |> assign(:animate_insert, true)
      |> stream_insert(:comments, loaded)
      |> assign(:n_comments, socket.assigns[:n_comments] + 1)

    if new_comment.user_id == socket.assigns[:current_user].id do
      {:noreply,
       new_socket
       |> put_flash(:info, "Your comment has been posted!")
       |> assign(:loading, false)
       |> assign_form(new_comment_changeset)}
    else
      {:noreply, new_socket}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "comment")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp post_date(%Post{published_on: nil} = post), do: post.inserted_at
  defp post_date(%Post{} = post), do: post.published_on

  defp comment_is_reply(%Comment{comment_id: nil}), do: false
  defp comment_is_reply(%Comment{}), do: true

  defp get_reply_to_id(%Comment{comment_id: nil} = comment), do: comment.id
  defp get_reply_to_id(comment), do: comment.comment_id

  defp featured_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp featured_image_url(%Image{optimized_image_path: optimized_path}),
    do: optimized_path

  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  # Format board position using the lookup map
  defp format_board_position(position) when is_atom(position) do
    Map.get(
      @board_position_to_title_lookup,
      position,
      String.capitalize(to_string(position))
    )
  end

  defp format_board_position(position) when is_binary(position) do
    position
    |> String.downcase()
    |> String.to_existing_atom()
    |> format_board_position()
  rescue
    ArgumentError -> String.capitalize(position)
  end

  defp format_board_position(_), do: ""
end
