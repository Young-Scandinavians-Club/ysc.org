defmodule YscWeb.NewsListLive do
  use YscWeb, :live_component

  alias Ysc.Posts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@post_count > 0} class="space-y-4">
        <div
          :for={{id, post} <- @streams.posts}
          class="flex flex-col md:flex-row gap-4 p-4 border border-zinc-200 rounded-lg hover:bg-zinc-50 transition-colors"
          id={id}
        >
          <div :if={post.featured_image} class="flex-shrink-0 w-full md:w-32">
            <.live_component
              id={"news-image-#{post.id}"}
              module={YscWeb.Components.Image}
              image_id={post.featured_image.id}
              aspect_class="aspect-[4/3]"
            />
          </div>

          <div class="flex-1 min-w-0">
            <div class="flex items-center text-sm text-zinc-500 mb-2">
              <time>
                <%= Timex.format!(
                  post.published_on,
                  "{WDshort}, {Mshort} {D}, {YYYY}"
                ) %>
              </time>
              <span class="mx-2">•</span>
              <span>
                by <%= post.author.first_name %> <%= post.author.last_name %>
              </span>
            </div>

            <.link navigate={~p"/posts/#{post.url_name}"} class="block">
              <h3 class="text-lg font-semibold text-zinc-900 hover:text-blue-600 transition-colors mb-2">
                <%= post.title %>
              </h3>
            </.link>

            <p class="text-zinc-600 text-sm line-clamp-2">
              <%= post.preview_text ||
                String.slice(post.rendered_body || "", 0, 150) <> "..." %>
            </p>
          </div>
        </div>
      </div>

      <div :if={@post_count == 0} class="text-center py-8">
        <div class="text-zinc-500">
          <.icon name="hero-newspaper" class="w-12 h-12 mx-auto mb-4 text-zinc-400" />
          <p class="text-lg font-medium text-zinc-600">No news articles yet</p>
          <p class="text-sm text-zinc-500">
            Check back soon for club updates and announcements!
          </p>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(_assigns, socket) do
    post_count = Posts.count_published_posts()
    # Show only 3 most recent posts on home page
    posts = Posts.list_posts(3)

    {:ok, socket |> stream(:posts, posts) |> assign(:post_count, post_count)}
  end
end
