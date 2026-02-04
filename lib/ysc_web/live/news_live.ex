defmodule YscWeb.NewsLive do
  use YscWeb, :live_view

  import YscWeb.Live.AsyncHelpers

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Media.Image

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
    <div class="py-6 md:py-12">
      <%!-- The "Masthead" Header --%>
      <div class="max-w-screen-xl mx-auto px-4 mb-16">
        <div class="text-center py-12 border-y border-zinc-200">
          <h1 class="text-6xl md:text-8xl font-black text-zinc-900 tracking-tighter">
            Club News
          </h1>
        </div>
      </div>

      <%!-- Loading skeleton for featured post --%>
      <div :if={!@async_data_loaded} class="max-w-screen-xl mx-auto px-4 mb-16">
        <div class="animate-pulse">
          <div class="relative aspect-[16/10] rounded-xl overflow-hidden bg-zinc-200">
            <div class="absolute inset-0 flex flex-col justify-end p-8 lg:p-12">
              <div class="max-w-3xl space-y-4">
                <div class="w-24 h-6 bg-zinc-300 rounded-lg"></div>
                <div class="w-32 h-4 bg-zinc-300 rounded"></div>
                <div class="w-3/4 h-12 bg-zinc-300 rounded"></div>
                <div class="w-full h-6 bg-zinc-300 rounded"></div>
                <div class="flex items-center gap-3 pt-4">
                  <div class="w-10 h-10 bg-zinc-300 rounded-full"></div>
                  <div class="space-y-2">
                    <div class="w-24 h-3 bg-zinc-300 rounded"></div>
                    <div class="w-16 h-2 bg-zinc-300 rounded"></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Modernized Featured Post - Impact Hero --%>
      <div
        :if={@async_data_loaded && @featured != nil}
        class="max-w-screen-xl mx-auto px-4 mb-16"
      >
        <div id="featured" class="group">
          <.link
            navigate={~p"/posts/#{@featured.url_name}"}
            class="block overflow-hidden rounded-2xl border border-zinc-100 bg-white shadow-xl transition-all duration-300 hover:shadow-2xl sm:border-0 sm:bg-transparent sm:shadow-none"
          >
            <div class="relative flex flex-col sm:block sm:aspect-[16/10] sm:rounded-xl sm:overflow-hidden sm:shadow-2xl">
              <%!-- Image container --%>
              <div class="relative aspect-[16/9] w-full overflow-hidden sm:absolute sm:inset-0 sm:aspect-auto sm:h-full">
                <canvas
                  id={"blur-hash-image-#{@featured.id}"}
                  src={get_blur_hash(@featured.featured_image)}
                  class="absolute inset-0 z-0 w-full h-full object-cover"
                  phx-hook="BlurHashCanvas"
                >
                </canvas>
                <img
                  src={featured_image_url(@featured.featured_image)}
                  id={"image-#{@featured.id}"}
                  phx-hook="BlurHashImage"
                  class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-105 transition-transform duration-700"
                  loading="eager"
                  alt={
                    if @featured.featured_image,
                      do:
                        @featured.featured_image.alt_text ||
                          @featured.featured_image.title ||
                          @featured.title || "Featured news image",
                      else: "Featured news image"
                  }
                />

                <%!-- Overlay gradient for text readability (hidden on mobile, shown on sm+) --%>
                <div class="hidden sm:block absolute inset-0 z-[2] bg-gradient-to-t from-zinc-900 via-zinc-900/40 to-transparent">
                </div>
              </div>

              <%!-- Content (stacked on mobile, overlaid on sm+) --%>
              <div class="relative z-[3] flex flex-col p-5 sm:absolute sm:inset-0 sm:justify-end sm:p-8 lg:p-12 transition-all duration-500">
                <div class="max-w-3xl">
                  <div class="flex items-center gap-2 mb-4">
                    <span class="px-2.5 py-1 bg-amber-600 text-white text-[10px] font-black uppercase tracking-widest rounded-lg shadow-sm sm:bg-amber-50/90 sm:backdrop-blur-md sm:border sm:border-amber-200 sm:text-amber-700">
                      <.icon name="hero-star-solid" class="w-3 h-3 inline me-1" />Pinned News
                    </span>
                  </div>

                  <div class="flex flex-wrap items-center gap-x-3 gap-y-1 mb-4 text-zinc-500 sm:text-white/80">
                    <span class="text-xs sm:text-sm font-black uppercase tracking-[0.1em]">
                      <%= Timex.format!(
                        @featured.published_on,
                        "{Mshort} {D}, {YYYY}"
                      ) %>
                    </span>
                    <span class="h-3 w-px bg-zinc-300 sm:bg-white/40"></span>
                    <span class="text-xs sm:text-sm font-bold uppercase tracking-widest">
                      <%= reading_time(@featured) %> min read
                    </span>
                  </div>

                  <h2 class="text-3xl font-black leading-tight tracking-tighter text-zinc-900 sm:text-zinc-50 sm:text-4xl lg:text-5xl xl:text-6xl mb-3 transition-colors duration-300">
                    <%= @featured.title %>
                  </h2>

                  <article class="text-zinc-600 sm:text-zinc-200 text-sm sm:text-base lg:text-lg leading-relaxed line-clamp-2 mb-6 max-w-2xl">
                    <%= raw(preview_text(@featured)) %>
                  </article>

                  <div class="flex items-center gap-3 pt-4 border-t border-zinc-100 sm:border-white/20">
                    <.user_avatar_image
                      email={@featured.author.email}
                      user_id={@featured.author.id}
                      country={@featured.author.most_connected_country}
                      class="w-8 h-8 sm:w-10 sm:h-10 rounded-full ring-2 ring-zinc-200 sm:ring-white/30"
                    />
                    <div>
                      <p class="text-xs sm:text-sm font-black text-zinc-900 sm:text-white leading-tight">
                        <%= String.capitalize(@featured.author.first_name || "") %>
                        <%= String.capitalize(@featured.author.last_name || "") %>
                      </p>
                      <p
                        :if={@featured.author.board_position}
                        class="text-[10px] sm:text-xs text-zinc-500 sm:text-white/80 font-medium mt-0.5"
                      >
                        YSC <%= format_board_position(
                          @featured.author.board_position
                        ) %>
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </.link>
        </div>
      </div>

      <%!-- Balanced Masonry Grid --%>
      <div class="max-w-screen-xl mx-auto px-4">
        <%!-- Loading skeleton for posts grid --%>
        <div
          :if={!@async_data_loaded}
          class="grid grid-cols-1 md:grid-cols-2 py-4 gap-8"
        >
          <%= for _i <- 1..4 do %>
            <div class="flex flex-col bg-white rounded-xl p-4 ring-1 ring-zinc-100 shadow-sm animate-pulse">
              <div class="aspect-[16/10] rounded-lg mb-8 bg-zinc-200"></div>
              <div class="px-4 pb-4 space-y-4">
                <div class="flex items-center gap-3">
                  <div class="w-16 h-3 bg-zinc-200 rounded"></div>
                  <div class="w-px h-3 bg-zinc-200"></div>
                  <div class="w-20 h-3 bg-zinc-200 rounded"></div>
                </div>
                <div class="w-3/4 h-8 bg-zinc-200 rounded"></div>
                <div class="w-full h-4 bg-zinc-200 rounded"></div>
                <div class="w-2/3 h-4 bg-zinc-200 rounded"></div>
                <div class="pt-6 border-t border-zinc-50 flex items-center gap-3">
                  <div class="w-8 h-8 bg-zinc-200 rounded-full"></div>
                  <div class="space-y-1">
                    <div class="w-20 h-3 bg-zinc-200 rounded"></div>
                    <div class="w-16 h-2 bg-zinc-200 rounded"></div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <div
          :if={@async_data_loaded && @post_count > 0}
          id="news-grid"
          class="grid grid-cols-1 md:grid-cols-2 py-4 gap-8"
          phx-viewport-top={@page > 1 && "prev-page"}
          phx-viewport-bottom={!@end_of_timeline? && "next-page"}
          phx-page-loading
        >
          <div
            :for={post <- @posts}
            id={"post-#{post.id}"}
            class="group flex flex-col bg-white rounded-xl p-4 ring-1 ring-zinc-100 shadow-sm hover:shadow-xl hover:ring-blue-500/30 transition-all duration-500"
          >
            <.link navigate={~p"/posts/#{post.url_name}"} class="block">
              <div class="relative aspect-[16/10] overflow-hidden rounded-lg mb-8">
                <canvas
                  id={"blur-hash-image-#{post.id}"}
                  src={get_blur_hash(post.featured_image)}
                  class="absolute inset-0 z-0 w-full h-full object-cover"
                  phx-hook="BlurHashCanvas"
                >
                </canvas>
                <img
                  src={featured_image_url(post.featured_image)}
                  id={"image-#{post.id}"}
                  loading="lazy"
                  phx-hook="BlurHashImage"
                  class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full transition-transform duration-700 group-hover:scale-110"
                  alt={
                    if post.featured_image,
                      do:
                        post.featured_image.alt_text || post.featured_image.title ||
                          post.title ||
                          "News article image",
                      else: "News article image"
                  }
                />
              </div>
            </.link>

            <div class="px-4 pb-4 flex flex-col flex-1">
              <div class="flex items-center gap-3 mb-4">
                <span class="text-[10px] font-black text-teal-600 uppercase tracking-[0.2em]">
                  <%= Timex.format!(post.published_on, "{Mshort} {D}") %>
                </span>
                <span class="h-3 w-px bg-zinc-200"></span>
                <span class="text-[10px] font-bold text-zinc-300 uppercase tracking-widest">
                  <%= reading_time(post) %> min read
                </span>
              </div>

              <.link
                navigate={~p"/posts/#{post.url_name}"}
                class="text-2xl font-black text-zinc-900 tracking-tighter leading-[1.1] mb-4 group-hover:text-blue-600 transition-colors"
              >
                <%= post.title %>
              </.link>

              <article class="text-zinc-500 text-sm leading-relaxed line-clamp-3 mb-8">
                <%= raw(preview_text(post)) %>
              </article>

              <div class="mt-auto pt-6 border-t border-zinc-50 flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <.user_avatar_image
                    email={post.author.email}
                    user_id={post.author.id}
                    country={post.author.most_connected_country}
                    class="w-8 h-8 rounded-full grayscale group-hover:grayscale-0 transition-all"
                  />
                  <div>
                    <p class="text-[10px] font-black text-zinc-400 group-hover:text-zinc-900 uppercase tracking-widest transition-colors leading-tight">
                      <%= String.capitalize(post.author.first_name || "") %>
                      <%= String.capitalize(post.author.last_name || "") %>
                    </p>
                    <p
                      :if={post.author.board_position}
                      class="text-[9px] text-zinc-400 group-hover:text-zinc-600 font-medium mt-0.5"
                    >
                      YSC <%= format_board_position(post.author.board_position) %>
                    </p>
                  </div>
                </div>
                <.icon
                  name="hero-arrow-right"
                  class="w-5 h-5 text-zinc-200 group-hover:text-blue-600 group-hover:translate-x-1 transition-all"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # Minimal assigns for fast initial static render
    socket =
      socket
      |> assign(:page_title, "News")
      |> assign(:featured, nil)
      |> assign(:post_count, 0)
      |> assign(:posts, [])
      |> assign(:page, 1)
      |> assign(:per_page, 10)
      |> assign(:end_of_timeline?, false)
      |> assign(:async_data_loaded, false)

    if connected?(socket) do
      # Load all data asynchronously after WebSocket connection
      {:ok, load_news_data_async(socket)}
    else
      {:ok, socket}
    end
  end

  # Load news data asynchronously
  defp load_news_data_async(socket) do
    start_async(socket, :load_news_data, fn ->
      # Run queries in parallel
      tasks = [
        {:featured,
         fn ->
           Posts.get_featured_post()
           |> Ysc.Repo.preload([:author, :featured_image])
         end},
        {:post_count, fn -> Posts.count_published_posts() end},
        {:posts, fn -> Posts.list_posts(0, 10) end}
      ]

      tasks
      |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
        Map.put(acc, key, value)
      end)
    end)
  end

  @impl true
  def handle_async(:load_news_data, {:ok, results}, socket) do
    featured = Map.get(results, :featured)
    post_count = Map.get(results, :post_count, 0)
    posts = Map.get(results, :posts, [])

    {:noreply,
     socket
     |> assign(:featured, featured)
     |> assign(:post_count, post_count)
     |> assign(:posts, posts)
     |> assign(:end_of_timeline?, length(posts) < socket.assigns.per_page)
     |> assign(:async_data_loaded, true)}
  end

  def handle_async(:load_news_data, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load news data async: #{inspect(reason)}")
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  @impl true
  def handle_event("next-page", _, socket) do
    {:noreply, paginate_posts(socket, socket.assigns.page + 1)}
  end

  def handle_event("prev-page", %{"_overran" => true}, socket) do
    {:noreply, paginate_posts(socket, 1)}
  end

  def handle_event("prev-page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, paginate_posts(socket, socket.assigns.page - 1)}
    else
      {:noreply, socket}
    end
  end

  defp paginate_posts(socket, new_page) when new_page >= 1 do
    %{per_page: per_page, page: cur_page} = socket.assigns

    # Posts.list_posts already preloads :author and :featured_image
    # Ecto will batch load these associations automatically
    new_posts = Posts.list_posts((new_page - 1) * per_page, per_page)

    case new_posts do
      [] ->
        socket
        |> assign(:end_of_timeline?, new_page >= cur_page)
        |> assign(:page, new_page)

      [_ | _] = new_posts ->
        # Get existing posts
        existing_posts = Map.get(socket.assigns, :posts, [])

        # Combine posts, avoiding duplicates by ID
        all_posts = existing_posts ++ new_posts
        unique_posts = Enum.uniq_by(all_posts, & &1.id)

        # Sort by published_on descending to maintain chronological order
        sorted_posts =
          Enum.sort_by(unique_posts, & &1.published_on, {:desc, DateTime})

        socket
        |> assign(:end_of_timeline?, length(new_posts) < per_page)
        |> assign(:page, new_page)
        |> assign(:posts, sorted_posts)
    end
  end

  # Do some magic to try and figure out what the preview text should be
  defp preview_text(%Post{preview_text: nil} = post) do
    Scrubber.scrub(post.raw_body, YscWeb.Scrubber.StripEverythingExceptText)
  end

  defp preview_text(post), do: post.preview_text

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp featured_image_url(nil), do: "/images/ysc_logo.png"

  defp featured_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp featured_image_url(%Image{optimized_image_path: optimized_path}),
    do: optimized_path

  # Calculate reading time based on word count (average 225 words per minute)
  # Uses rendered_body if available, otherwise falls back to raw_body
  defp reading_time(%Post{} = post) do
    cond do
      post.rendered_body && post.rendered_body != "" ->
        word_count = count_words_in_html(post.rendered_body)
        calculate_minutes(word_count)

      post.raw_body && post.raw_body != "" ->
        # Strip HTML tags and count words
        text =
          Scrubber.scrub(
            post.raw_body,
            YscWeb.Scrubber.StripEverythingExceptText
          )

        word_count = count_words_in_text(text)
        calculate_minutes(word_count)

      post.preview_text && post.preview_text != "" ->
        word_count = count_words_in_html(post.preview_text)
        calculate_minutes(word_count)

      true ->
        "1"
    end
  end

  # Count words in HTML by stripping tags and counting
  defp count_words_in_html(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/&[a-z]+;/i, " ")
    |> String.replace(~r/&#\d+;/, " ")
    |> count_words_in_text
  end

  # Count words in plain text
  defp count_words_in_text(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  # Calculate minutes from word count (225 words per minute)
  defp calculate_minutes(word_count) when word_count <= 0, do: "1"

  defp calculate_minutes(word_count) do
    minutes = max(1, round(word_count / 225.0))
    Integer.to_string(minutes)
  end

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
