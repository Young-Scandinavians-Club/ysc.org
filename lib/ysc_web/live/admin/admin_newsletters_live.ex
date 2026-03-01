defmodule YscWeb.AdminNewslettersLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
      board_position={@current_user.board_position}
    >
      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Newsletters
        </h1>
      </div>

      <div class="w-full">
        <p class="text-zinc-600">🚧 Under construction 🚧</p>
      </div>
    </.side_menu>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Newsletters")
     |> assign(:active_page, :newsletters)}
  end
end
