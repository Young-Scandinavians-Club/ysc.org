defmodule QueryConsoleWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use QueryConsoleWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :ysc_admin_url, QueryConsole.SSO.admin_url())

    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 min-h-12 border-b border-base-300">
      <div class="flex-1 flex items-center gap-3">
        <a
          id="back-to-admin"
          href={@ysc_admin_url}
          class="btn btn-ghost btn-xs gap-1"
        >
          <.icon name="hero-arrow-left" class="w-3.5 h-3.5" /> Admin
        </a>
        <a href="/" class="flex items-center gap-2">
          <span class="text-sm font-semibold tracking-wide">YSC Query Console</span>
        </a>
      </div>
      <div class="flex-none">
        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-4 sm:px-6 lg:px-8">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  Root layout for Lotus Web with YSC Admin + Sign out chrome.

  Chrome sits outside LiveView `@inner_content` so patches do not remove it.
  """
  def lotus_root(assigns) do
    assigns =
      assigns
      |> assign_new(:csp_nonces, fn -> %{style: nil, script: nil} end)
      |> assign_new(:current_user, fn -> nil end)
      |> assign(:ysc_admin_url, QueryConsole.SSO.admin_url())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta http-equiv="X-UA-Compatible" content="IE=edge" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={get_csrf_token()} />

        <title>{assigns[:page_title] || "YSC Query Console"}</title>

        <style phx-track-static nonce={@csp_nonces[:style]}>
          <%= raw(Lotus.Web.Layouts.render("app.css")) %>
        </style>
        <script
          src="https://cdn.jsdelivr.net/npm/@tailwindplus/elements@1"
          type="module"
          nonce={@csp_nonces[:script]}
        >
        </script>
      </head>

      <body class="h-full antialiased bg-gray-200 dark:bg-black text-text-light dark:text-text-dark transition-colors duration-200 ease-out">
        <div class="flex items-center justify-between gap-3 px-4 py-2 bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-700 text-sm">
          <a
            id="back-to-admin"
            href={@ysc_admin_url}
            class="inline-flex items-center gap-1 px-2 py-1 rounded-md font-medium text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700"
          >
            ← Admin
          </a>
          <div class="flex items-center gap-3">
            <span
              :if={@current_user}
              id="signed-in-as"
              class="text-gray-500 dark:text-gray-400 truncate max-w-xs"
              title={@current_user.email}
            >
              {@current_user.display_name || @current_user.email}
            </span>
            <a
              id="sign-out"
              href={~p"/auth/logout"}
              class="inline-flex items-center px-2 py-1 rounded-md font-medium text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700"
            >
              Sign out
            </a>
          </div>
        </div>
        {@inner_content}
      </body>

      <script phx-track-static type="text/javascript" nonce={@csp_nonces[:script]}>
        <%= raw(Lotus.Web.Layouts.render("app.js")) %>
      </script>
    </html>
    """
  end
end
