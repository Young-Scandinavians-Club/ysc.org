defmodule YscWeb.Components.News.NewsCard do
  @moduledoc """
  Reusable news card component that matches the design used in NewsLive.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents
  import Phoenix.HTML

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Media.Image
  alias HtmlSanitizeEx.Scrubber

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
      "group flex flex-col bg-white rounded-xl p-4 transition-all duration-500 border border-transparent hover:border-blue-500/20",
      if(@variant == "elevated",
        do: "shadow-lg hover:shadow-2xl hover:-translate-y-1",
        else:
          "shadow-[0_8px_30px_rgb(0,0,0,0.04)] hover:shadow-xl hover:-translate-y-2"
      ),
      @class
    ]}>
      <.link navigate={~p"/posts/#{@post.url_name}"} class="block">
        <div class="relative aspect-[16/10] overflow-hidden rounded-lg mb-8">
          <canvas
            id={"blur-hash-image-#{@post.id}"}
            src={get_blur_hash(@post.featured_image)}
            class="absolute inset-0 z-0 w-full h-full object-cover"
            phx-hook="BlurHashCanvas"
          >
          </canvas>
          <img
            src={featured_image_url(@post.featured_image)}
            id={"image-#{@post.id}"}
            loading="lazy"
            phx-hook="BlurHashImage"
            class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full transition-transform duration-700 group-hover:scale-110"
            alt={
              if @post.featured_image,
                do:
                  @post.featured_image.alt_text || @post.featured_image.title ||
                    @post.title ||
                    "News article image",
                else: "News article image"
            }
          />
        </div>
      </.link>

      <div class="px-4 pb-4 flex flex-col flex-1">
        <div class="flex items-center gap-3 mb-4">
          <span class="text-[10px] font-black text-teal-600 uppercase tracking-[0.2em]">
            <%= Timex.format!(@post.published_on, "{Mshort} {D}") %>
          </span>
          <span class="h-3 w-px bg-zinc-200"></span>
          <span class="text-[10px] font-bold text-zinc-300 uppercase tracking-widest">
            <%= @reading_time %> min read
          </span>
        </div>

        <.link
          navigate={~p"/posts/#{@post.url_name}"}
          class="text-2xl font-black text-zinc-900 tracking-tighter leading-[1.1] mb-4 group-hover:text-blue-600 transition-colors"
        >
          <%= @post.title %>
        </.link>

        <article class="text-zinc-500 text-sm leading-relaxed line-clamp-3 mb-8">
          <%= raw(@preview_text) %>
        </article>

        <div class="mt-auto pt-6 border-t border-zinc-50 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <.user_avatar_image
              email={@post.author.email}
              user_id={@post.author.id}
              country={@post.author.most_connected_country}
              class="w-8 h-8 rounded-full grayscale group-hover:grayscale-0 transition-all"
            />
            <div>
              <p class="text-[10px] font-black text-zinc-400 group-hover:text-zinc-900 uppercase tracking-widest transition-colors leading-tight">
                <%= String.capitalize(@post.author.first_name || "") %>
                <%= String.capitalize(@post.author.last_name || "") %>
              </p>
              <p
                :if={@post.author.board_position}
                class="text-[9px] text-zinc-400 group-hover:text-zinc-600 font-medium mt-0.5"
              >
                YSC <%= format_board_position(@post.author.board_position) %>
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

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash
  defp get_blur_hash(_), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp featured_image_url(nil), do: "/images/ysc_logo.png"

  defp featured_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp featured_image_url(%Image{optimized_image_path: optimized_path}),
    do: optimized_path

  defp featured_image_url(_), do: "/images/ysc_logo.png"

  # Calculate reading time based on word count (average 225 words per minute)
  defp reading_time(post) do
    cond do
      post.rendered_body && post.rendered_body != "" ->
        word_count = count_words_in_html(post.rendered_body)
        calculate_minutes(word_count)

      post.raw_body && post.raw_body != "" ->
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

  defp count_words_in_html(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/&[a-z]+;/i, " ")
    |> String.replace(~r/&#\d+;/, " ")
    |> count_words_in_text
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

  defp preview_text(%{preview_text: nil} = post) do
    if post.raw_body do
      Scrubber.scrub(post.raw_body, YscWeb.Scrubber.StripEverythingExceptText)
    else
      ""
    end
  end

  defp preview_text(post) do
    post.preview_text || ""
  end

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
