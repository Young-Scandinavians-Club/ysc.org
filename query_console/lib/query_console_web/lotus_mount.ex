defmodule QueryConsoleWeb.LotusMount do
  @moduledoc """
  Mounts Lotus Web with our root layout (Admin + Sign out chrome).

  Upstream `lotus_dashboard/2` hardcodes `Lotus.Web.Layouts` as the root layout;
  this helper mirrors that macro but points at `QueryConsoleWeb.Layouts.lotus_root/1`.
  """

  @doc false
  defmacro lotus_dashboard(path, opts \\ []) do
    quote bind_quoted: binding() do
      # Lotus.Web.Helpers.lotus_path/2 originally builds "#{prefix}/#{route}". Mounted at
      # "/" that is either "//queries/new" (prefix "/") or empty home href (prefix "").
      # We keep prefix "" here and redefine Helpers (lib/lotus_web/helpers.ex) to join
      # root paths correctly: "" → "/", "queries/new" → "/queries/new".
      prefix =
        case Phoenix.Router.scoped_path(__MODULE__, path) do
          "/" -> ""
          other -> String.trim_trailing(other, "/")
        end

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]
        import Phoenix.Router, only: [get: 3]

        {session_name, session_opts, public_session_opts, route_opts} =
          Lotus.Web.Router.__options__(prefix, opts)

        session_opts =
          Keyword.put(session_opts, :root_layout, {QueryConsoleWeb.Layouts, :lotus_root})

        public_session_opts =
          Keyword.put(public_session_opts, :root_layout, {QueryConsoleWeb.Layouts, :lotus_root})

        get("/export/csv", Lotus.Web.ExportController, :csv)

        live_session :"#{session_name}_public", public_session_opts do
          live("/public/:token", Lotus.Web.PublicDashboardLive, :show)
        end

        live_session session_name, session_opts do
          live("/", Lotus.Web.DashboardLive, :home, route_opts)
          live("/:page", Lotus.Web.DashboardLive, :index, route_opts)
          live("/:page/:id", Lotus.Web.DashboardLive, :show, route_opts)
        end
      end
    end
  end
end
