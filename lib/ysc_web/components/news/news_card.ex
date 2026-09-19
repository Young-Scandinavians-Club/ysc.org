defmodule YscWeb.Components.News.NewsCard do
  @moduledoc """
  Reusable news card component that matches the design used in NewsLive.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Accounts
  alias Ysc.Accounts.UserDisplay
  alias Ysc.Posts.ReadingTime
  alias YscWeb.PlainText

  attr :post, :any, required: true
  attr :class, :string, default: nil

  attr :variant, :string,
    default: "default",
    doc: "Card variant: 'default' or 'elevated'"

  def news_card(assigns) do
    assigns =
      assigns
      |> assign(:reading_time, ReadingTime.minutes(assigns.post))
      |> assign(:preview_text, preview_text(assigns.post))

    ~H"""
    <div class={[
      "group flex flex-col bg-white rounded-xl p-4 border border-zinc-100 hover:border-zinc-200 transition-colors duration-150",
      @class
    ]}>
      <.link navigate={~p"/posts/#{@post.url_name}"} class="block">
        <div class="relative aspect-16/10 overflow-hidden rounded-xl mb-8">
          <.live_component
            id={"news-card-image-#{@post.id}"}
            module={YscWeb.Components.Image}
            image={@post.featured_image}
            aspect_class="h-full"
            preferred_type={:optimized}
            sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
          />
        </div>
      </.link>

      <div class="px-4 pb-4 flex flex-col flex-1">
        <div class="flex items-center gap-3 mb-4">
          <span class="text-sm font-black text-blue-600 uppercase tracking-[0.2em]">
            {if @post.published_on,
              do: Timex.format!(@post.published_on, "{Mshort} {D}"),
              else: ""}
          </span>
          <span class="h-3 w-px bg-zinc-200"></span>
          <span
            id={"news-card-reading-time-#{@post.id}"}
            class="text-sm font-bold text-zinc-500 uppercase tracking-widest"
          >
            {@reading_time} min read
          </span>
        </div>

        <.link
          navigate={~p"/posts/#{@post.url_name}"}
          class="text-2xl font-black text-zinc-900 tracking-tight leading-[1.1] mb-4 group-hover:text-blue-600 group-hover:underline transition-colors"
        >
          {@post.title}
        </.link>

        <article class="text-zinc-500 text-sm leading-relaxed line-clamp-3 whitespace-pre-line mb-8">
          {@preview_text}
        </article>

        <div class="mt-auto pt-6 border-t border-zinc-50 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <.user_avatar_image
              email={@post.author.email}
              user_id={@post.author.id}
              country={@post.author.most_connected_country}
              class="w-8 h-8 rounded-full transition-all"
            />
            <div>
              <p class="text-sm font-black text-zinc-500 group-hover:text-zinc-900 uppercase tracking-widest transition-colors leading-tight">
                {UserDisplay.full_name(@post.author)}
              </p>
              <p
                :if={@post.board_position_at_publish}
                class="text-sm text-zinc-500 group-hover:text-zinc-600 font-medium mt-0.5"
              >
                YSC {Accounts.format_board_position(@post.board_position_at_publish)}
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
    """
  end

  defp preview_text(post), do: PlainText.from_post(post)
end
