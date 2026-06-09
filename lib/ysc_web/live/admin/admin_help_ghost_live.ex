defmodule YscWeb.AdminHelpGhostLive do
  @moduledoc """
  Renders admin help ghost previews — real admin layouts with skeleton
  placeholders instead of live data. Embedded in guide iframes at a fixed
  1280×800 viewport.
  """
  use YscWeb, :admin_live_view

  alias YscWeb.AdminHelp.Ghost.Previews
  alias YscWeb.AdminHelp.Ghost.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Help preview")
     |> assign(:embed?, false)
     |> assign(:preview_slug, nil)
     |> assign(:active_page, :dashboard)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    slug = slug_from_params(params)
    embed? = Map.get(params, "embed") == "1"

    case Registry.fetch(slug) do
      {:ok, %{active_page: active_page} = meta} ->
        {:noreply,
         socket
         |> assign(:embed?, embed?)
         |> assign(:preview_slug, slug)
         |> assign(:active_page, active_page || :dashboard)
         |> assign(:public_preview?, Map.get(meta, :public?, false))}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Preview not found.")
         |> push_navigate(to: ~p"/admin/help")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="admin-help-ghost-root"
      class={[
        @embed? && "admin-help-ghost-embed",
        !@embed? && "min-h-screen"
      ]}
    >
      <%= if @public_preview? do %>
        <Previews.preview slug={@preview_slug} />
      <% else %>
        <.side_menu
          active_page={@active_page}
          user={@current_user}
          role={@admin_role}
        >
          <Previews.preview slug={@preview_slug} />
        </.side_menu>
      <% end %>
    </div>
    """
  end

  defp slug_from_params(%{"name" => name}) when is_binary(name), do: name
  defp slug_from_params(_), do: ""
end
