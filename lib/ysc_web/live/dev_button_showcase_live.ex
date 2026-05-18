defmodule YscWeb.DevButtonShowcaseLive do
  @moduledoc false
  # Visual reference for `<.button>` — only routed when `config :ysc, dev_routes: true` (dev).

  use YscWeb, :live_view

  @colors ~w(blue red green amber zinc teal)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "[Dev] Button showcase")
     |> assign(:colors, @colors)}
  end

  @impl true
  def handle_event("showcase-noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("showcase-slow", _params, socket) do
    Process.sleep(800)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <div class="max-w-5xl mx-auto px-4 py-10 space-y-12">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">
            Button component showcase
          </h1>
          <p class="mt-2 text-sm text-zinc-600 leading-relaxed">
            Dev-only page (<code class="text-xs bg-zinc-100 px-1 rounded">/dev/button-showcase</code>).
            <strong>Interactive</strong>
            uses a slow handler so LiveView applies real loading classes.
            <strong>Forced</strong>
            adds a static
            <code class="text-xs bg-zinc-100 px-1 rounded">phx-click-loading</code>
            or
            <code class="text-xs bg-zinc-100 px-1 rounded">phx-submit-loading</code>
            class for a frozen snapshot.
          </p>
        </div>

        <section class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
            Solid variant
          </h2>
          <.showcase_table>
            <%= for color <- @colors do %>
              <tr class="border-b border-zinc-100 align-middle">
                <td class="py-3 pr-4 text-sm font-medium text-zinc-700 whitespace-nowrap">
                  {color}
                </td>
                <td class="py-3 pr-4">
                  <.button
                    color={color}
                    phx-click="showcase-slow"
                    id={"showcase-solid-#{color}-live"}
                  >
                    Click ({color})
                  </.button>
                </td>
                <td class="py-3">
                  <.button
                    color={color}
                    phx-click="showcase-noop"
                    class="phx-click-loading"
                    id={"showcase-solid-#{color}-forced"}
                  >
                    Loading ({color})
                  </.button>
                </td>
              </tr>
            <% end %>
          </.showcase_table>
        </section>

        <section class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
            Outline variant
          </h2>
          <.showcase_table>
            <%= for color <- @colors do %>
              <tr class="border-b border-zinc-100 align-middle">
                <td class="py-3 pr-4 text-sm font-medium text-zinc-700 whitespace-nowrap">
                  {color}
                </td>
                <td class="py-3 pr-4">
                  <.button
                    variant="outline"
                    color={color}
                    phx-click="showcase-slow"
                    id={"showcase-outline-#{color}-live"}
                  >
                    Click ({color})
                  </.button>
                </td>
                <td class="py-3">
                  <.button
                    variant="outline"
                    color={color}
                    phx-click="showcase-noop"
                    class="phx-click-loading"
                    id={"showcase-outline-#{color}-forced"}
                  >
                    Loading ({color})
                  </.button>
                </td>
              </tr>
            <% end %>
          </.showcase_table>
        </section>

        <section class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
            Link-style buttons (navigate / patch / href)
          </h2>
          <.showcase_table>
            <tr class="border-b border-zinc-100 align-middle">
              <td class="py-3 pr-4 text-sm font-medium text-zinc-700">navigate</td>
              <td class="py-3 pr-4">
                <.button navigate={~p"/"} id="showcase-nav-live">
                  Home
                </.button>
              </td>
              <td class="py-3">
                <.button
                  navigate={~p"/"}
                  class="phx-click-loading"
                  id="showcase-nav-forced"
                >
                  Home (loading)
                </.button>
              </td>
            </tr>
            <tr class="border-b border-zinc-100 align-middle">
              <td class="py-3 pr-4 text-sm font-medium text-zinc-700">patch</td>
              <td class="py-3 pr-4">
                <.button patch="/dev/button-showcase" id="showcase-patch-live">
                  Patch here
                </.button>
              </td>
              <td class="py-3">
                <.button
                  patch="/dev/button-showcase"
                  class="phx-click-loading"
                  id="showcase-patch-forced"
                >
                  Patch (loading)
                </.button>
              </td>
            </tr>
            <tr class="border-b border-zinc-100 align-middle">
              <td class="py-3 pr-4 text-sm font-medium text-zinc-700">href</td>
              <td class="py-3 pr-4">
                <.button href="#showcase-href-anchor" id="showcase-href-live">
                  Anchor link
                </.button>
              </td>
              <td class="py-3">
                <.button
                  href="#showcase-href-anchor"
                  class="phx-click-loading"
                  id="showcase-href-forced"
                >
                  Anchor (loading)
                </.button>
              </td>
            </tr>
          </.showcase_table>
          <p id="showcase-href-anchor" class="text-xs text-zinc-400">
            Href anchor target (page bottom).
          </p>
        </section>

        <section class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
            type="submit" (structured loading)
          </h2>
          <.showcase_table>
            <tr class="border-b border-zinc-100 align-middle">
              <td class="py-3 pr-4 text-sm font-medium text-zinc-700">
                live submit
              </td>
              <td class="py-3 pr-4">
                <.form
                  for={to_form(%{}, as: :showcase_live)}
                  phx-submit="showcase-slow"
                  id="showcase-submit-form-live"
                >
                  <.button
                    type="submit"
                    phx-disable-with="Submitting..."
                    id="showcase-submit-live"
                  >
                    Submit slow
                  </.button>
                </.form>
              </td>
              <td class="py-3">
                <.form
                  for={to_form(%{}, as: :showcase_forced)}
                  id="showcase-submit-form-forced"
                >
                  <.button
                    type="submit"
                    phx-disable-with="Submitting..."
                    class="phx-submit-loading"
                    id="showcase-submit-forced"
                  >
                    Submit (loading)
                  </.button>
                </.form>
              </td>
            </tr>
          </.showcase_table>
        </section>

        <section class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
            Custom loading label
          </h2>
          <div class="flex flex-wrap gap-4 items-center">
            <.button
              phx-click="showcase-slow"
              phx-disable-with="Saving..."
              id="showcase-custom-disable-with"
            >
              phx-disable-with
            </.button>
            <.button
              phx-click="showcase-slow"
              loading_text="Archiving..."
              id="showcase-custom-loading-text"
            >
              loading_text assign
            </.button>
          </div>
        </section>

        <section class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
            Disabled
          </h2>
          <div class="flex flex-wrap gap-4 items-center">
            <.button disabled type="button" id="showcase-disabled-solid">
              Solid disabled
            </.button>
            <.button
              variant="outline"
              color="zinc"
              disabled
              type="button"
              id="showcase-disabled-outline"
            >
              Outline disabled
            </.button>
          </div>
        </section>

        <section class="space-y-4">
          <h2 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
            No LiveView binding (no structured loading)
          </h2>
          <p class="text-sm text-zinc-600">
            Plain
            <code class="text-xs bg-zinc-100 px-1 rounded">
              {"type=\"button\""}
            </code>
            with no <code class="text-xs bg-zinc-100 px-1 rounded">phx-*</code>
            — default label is not injected; markup stays a single label span.
          </p>
          <.button type="button" id="showcase-plain">
            Decorative
          </.button>
        </section>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true

  def showcase_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-lg border border-zinc-200">
      <table class="min-w-full text-left">
        <thead class="bg-zinc-50 text-xs font-semibold uppercase tracking-wide text-zinc-500">
          <tr>
            <th class="py-2 px-3">Variant / case</th>
            <th class="py-2 px-3">Interactive (slow)</th>
            <th class="py-2 px-3">Forced loading class</th>
          </tr>
        </thead>
        <tbody>
          {render_slot(@inner_block)}
        </tbody>
      </table>
    </div>
    """
  end
end
