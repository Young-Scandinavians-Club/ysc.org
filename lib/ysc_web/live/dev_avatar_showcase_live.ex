defmodule YscWeb.DevAvatarShowcaseLive do
  @moduledoc false
  # Visual reference for Nordic avatar identity treatments — only routed when dev_routes is enabled.

  use YscWeb, :live_view

  alias Ysc.Accounts.UserDisplay

  @countries ~w(SE NO DK FI IS)
  @sizes ["w-8 h-8", "w-10 h-10", "w-14 h-14", "w-24 h-24"]
  @variants [
    {:ring, "Flag-color ring",
     "Circular avatar with a thin conic-gradient ring in the country's flag colors."},
    {:badge, "Corner badge",
     "Circular avatar with a small flag chip at the bottom-right."},
    {:peek, "Rounded square + flag peek",
     "Rounded-square photo with the flag strip peeking on the right edge."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "[Dev] Avatar identity showcase")
     |> assign(:countries, @countries)
     |> assign(:sizes, @sizes)
     |> assign(:variants, @variants)
     |> assign(:sample_photo_url, ~p"/images/default_avatars/norway_fjord.webp")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <div class="max-w-6xl mx-auto px-4 py-10 space-y-14">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">
            Nordic avatar identity showcase
          </h1>
          <p class="mt-2 text-sm text-zinc-600 leading-relaxed max-w-3xl">
            Dev-only page (<code class="text-xs bg-zinc-100 px-1 rounded">/dev/avatar-showcase</code>).
            Compare three treatments driven by <code class="text-xs bg-zinc-100 px-1 rounded">most_connected_country</code>.
            Production uses the <strong>corner badge</strong>
            via <code class="text-xs bg-zinc-100 px-1 rounded">&lt;.user_avatar_image&gt;</code>.
          </p>
        </div>

        <%= for {variant, title, description} <- @variants do %>
          <section class="space-y-6" id={"variant-#{variant}"}>
            <div>
              <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
                {title}
              </h2>
              <p class="mt-2 text-sm text-zinc-600">{description}</p>
            </div>

            <div class="space-y-3">
              <h3 class="text-sm font-semibold text-zinc-700 uppercase tracking-wide">
                Default country images
              </h3>
              <.showcase_grid>
                <%= for country <- @countries do %>
                  <.showcase_country_row
                    country={country}
                    sizes={@sizes}
                    variant={variant}
                  />
                <% end %>
              </.showcase_grid>
            </div>

            <div class="space-y-3">
              <h3 class="text-sm font-semibold text-zinc-700 uppercase tracking-wide">
                Custom photo + country cue
              </h3>
              <p class="text-xs text-zinc-500">
                Same landscape photo for every country so you can judge identity on uploaded avatars.
              </p>
              <.showcase_grid>
                <%= for country <- @countries do %>
                  <.showcase_country_row
                    country={country}
                    sizes={@sizes}
                    variant={variant}
                    avatar_url={@sample_photo_url}
                  />
                <% end %>
              </.showcase_grid>
            </div>

            <div :if={variant == :ring} class="space-y-3">
              <h3 class="text-sm font-semibold text-zinc-700 uppercase tracking-wide">
                Ring + semantic status rings
              </h3>
              <p class="text-xs text-zinc-500">
                Event pages use blue (you) and amber (host) rings today — see how the flag ring stacks.
              </p>
              <div class="flex flex-wrap items-end gap-8">
                <.semantic_ring_example
                  label="You (blue)"
                  country="SE"
                  variant={variant}
                  avatar_url={@sample_photo_url}
                  extra_class="ring-2 ring-blue-500 ring-offset-2 ring-offset-white"
                />
                <.semantic_ring_example
                  label="Host (amber)"
                  country="NO"
                  variant={variant}
                  avatar_url={@sample_photo_url}
                  extra_class="ring-2 ring-amber-400 ring-offset-2 ring-offset-white"
                />
              </div>
            </div>
          </section>
        <% end %>

        <section class="space-y-4 border-t border-zinc-200 pt-8">
          <h2 class="text-lg font-semibold text-zinc-800">Flag color palette</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
            <%= for country <- @countries do %>
              <div class="rounded-lg border border-zinc-200 bg-white p-4 space-y-3">
                <p class="text-sm font-semibold text-zinc-900">
                  {country} · {UserDisplay.country_label(country)}
                </p>
                <div class="flex h-8 rounded overflow-hidden ring-1 ring-zinc-200">
                  <%= for color <- country_flag_colors(country) do %>
                    <span class="flex-1" style={"background-color: #{color};"} />
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :country, :string, required: true
  attr :sizes, :list, required: true
  attr :variant, :atom, required: true
  attr :avatar_url, :string, default: nil

  defp showcase_country_row(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-100 bg-white p-4 space-y-3">
      <p class="text-sm font-medium text-zinc-800">
        {@country} · {UserDisplay.country_label(@country)}
      </p>
      <div class="flex flex-wrap items-end gap-4">
        <%= for size <- @sizes do %>
          <div class="flex flex-col items-center gap-2">
            <.user_avatar_identity
              variant={@variant}
              country={@country}
              user_id="42"
              avatar_url={@avatar_url}
              class={size}
            />
            <span class="text-[10px] text-zinc-400 font-mono">{size}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :country, :string, required: true
  attr :variant, :atom, required: true
  attr :avatar_url, :string, required: true
  attr :extra_class, :string, required: true

  defp semantic_ring_example(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2">
      <div class={@extra_class}>
        <.user_avatar_identity
          variant={@variant}
          country={@country}
          avatar_url={@avatar_url}
          class="w-14 h-14"
        />
      </div>
      <span class="text-xs text-zinc-500">{@label}</span>
    </div>
    """
  end

  slot :inner_block, required: true

  defp showcase_grid(assigns) do
    ~H"""
    <div class="grid gap-4 lg:grid-cols-2">
      {render_slot(@inner_block)}
    </div>
    """
  end
end
