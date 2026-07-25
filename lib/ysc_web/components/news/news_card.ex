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
  alias YscWeb.PlainText

  attr :post, :any, required: true
  attr :class, :string, default: nil

  attr :variant, :string,
    default: "default",
    doc: "Card variant: 'default' or 'elevated'"

  def news_card(assigns) do
    assigns =
      assigns
      |> assign(:reading_time, reading_time(assigns.post))
      |> assign(:preview_text, preview_text(assigns.post))

    ~H"""
    <div class={[
      "group flex flex-col bg-white rounded-xl p-4 border border-zinc-100 hover:border-zinc-200 transition-colors duration-150",
      @class
    ]}>
      <.link navigate={~p"/posts/#{@post.url_name}"} class="block">
        <div class="relative aspect-[16/10] overflow-hidden rounded-xl mb-8">
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
          <span class="text-sm font-bold text-zinc-500 uppercase tracking-widest">
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
                {Ysc.title_case(@post.author.first_name || "")}
                {Ysc.title_case(@post.author.last_name || "")}
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

  # Calculate reading time based on word count (average 225 words per minute)
  defp reading_time(post) do
    cond do
      post.rendered_body && post.rendered_body != "" ->
        word_count = count_words_in_html(post.rendered_body)
        calculate_minutes(word_count)

      post.raw_body && post.raw_body != "" ->
        word_count =
          post.raw_body |> PlainText.from_html() |> count_words_in_text()

        calculate_minutes(word_count)

      post.preview_text && post.preview_text != "" ->
        word_count =
          post.preview_text |> PlainText.from_html() |> count_words_in_text()

        calculate_minutes(word_count)

      true ->
        "1"
    end
  end

  defp count_words_in_html(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/&[a-z]+;/i, " ")
    |> String.replace(~r/&#\d+;/, " ")
    |> count_words_in_text()
  end

  defp count_words_in_text(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp calculate_minutes(word_count) when word_count <= 0, do: "1"

  defp calculate_minutes(word_count) do
    minutes = max(1, round(word_count / 225.0))
    Integer.to_string(minutes)
  end

  defp preview_text(post), do: PlainText.from_post(post)
end
