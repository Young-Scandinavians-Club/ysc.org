defmodule YscWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use YscWeb, :controller
      use YscWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths,
    do:
      ~w(assets fonts images video documents favicon.ico site.webmanifest favicon-16x16.png favicon-32x32.png apple-touch-icon.png android-chrome-512x512.png android-chrome-192x192.png)

  def router do
    quote do
      use Phoenix.Router, helpers: true

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: YscWeb.Layouts]

      import Plug.Conn
      import YscWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {YscWeb.Layouts, :app}

      unquote(html_helpers())

      # Global event: "clear" is sent by the client-error flash in the layout when dismissed.
      # No-op on the server; the UI is updated via JS. Prevents FunctionClauseError in any LiveView.
      @impl true
      def handle_event("clear", _params, socket) do
        {:noreply, socket}
      end

      # Swoosh.Adapters.Test delivers to processes in the $callers chain (see adapter docs).
      @impl true
      def handle_info({:email, _email}, socket), do: {:noreply, socket}

      def handle_info({:emails, _emails}, socket), do: {:noreply, socket}
    end
  end

  def admin_live_view do
    quote do
      use Phoenix.LiveView,
        layout: {YscWeb.Layouts, :admin_app}

      unquote(html_helpers())
      import YscWeb.AdminComponents

      import YscWeb.AdminFlopHelpers,
        only: [
          non_flop_params: 1,
          title_search_query: 1,
          build_title_search_filter_params: 2,
          merge_date_range_into_params: 3,
          compact_filter_params: 1,
          merge_title_filter_into_params: 2
        ]

      import YscWeb.AdminHelpComponents

      # Global event: "clear" is sent by the client-error flash in the layout when dismissed.
      # No-op on the server; the UI is updated via JS. Prevents FunctionClauseError in any LiveView.
      @impl true
      def handle_event("clear", _params, socket) do
        {:noreply, socket}
      end

      # Swoosh.Adapters.Test delivers to processes in the $callers chain (see adapter docs).
      @impl true
      def handle_info({:email, _email}, socket), do: {:noreply, socket}

      def handle_info({:emails, _emails}, socket), do: {:noreply, socket}
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import YscWeb.CoreComponents
      import YscWeb.Components.Autocomplete
      import YscWeb.PaymentMethodComponents
      import YscWeb.Gettext

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: YscWeb.Endpoint,
        router: YscWeb.Router,
        statics: YscWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
