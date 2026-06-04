defmodule YscWeb.Layouts do
  use YscWeb, :html

  import LiveToast, only: [toast_group: 1]

  embed_templates "layouts/*"

  @doc """
  Builds toasts_sync and flash for the toast group. Promotes flash messages that
  have a custom title (from redirects via YscWeb.Flash) into full toasts with
  title and icon. Welcome-back message gets a dedicated title and icon.
  Uses stable UUIDs for promoted toasts so re-renders don't duplicate.

  Flash keys for promoted messages are **left in** `flash` passed to `toast_group`. The
  bundled `LiveToast.LiveComponent` merges each `toasts_sync` item with the matching
  flash entry, streams the rich toast, then clears that flash key—if we stripped here
  first, redirect toasts (e.g. OAuth errors) would never match and would not render.
  """
  def toasts_sync_with_flash(assigns) do
    base = assigns[:toasts_sync] || []
    flash = assigns[:flash] || %{}
    flash = normalize_flash_keys(flash)

    info_msg = flash["info"]

    {toasts_sync, flash_out} =
      if info_msg && is_binary(info_msg) &&
           String.contains?(info_msg, "Welcome back") do
        {[welcome_toast(info_msg) | base], flash}
      else
        promoted = promote_flash_to_toasts(flash)
        {promoted ++ base, flash}
      end

    {toasts_sync, flash_out}
  end

  defp welcome_toast(info_msg) do
    %LiveToast{
      kind: :info,
      msg: info_msg,
      title: "Welcome back! 👋",
      icon: &YscWeb.CoreComponents.flash_toast_icon_success/1,
      uuid: stable_toast_uuid(:info, info_msg, "Welcome back! 👋"),
      sync: true,
      duration: 6000
    }
  end

  defp promote_flash_to_toasts(flash) do
    [:info, :error, :warning]
    |> Enum.flat_map(fn kind ->
      msg = flash[to_string(kind)]
      title = flash["#{kind}_toast_title"]

      if is_binary(msg) && is_binary(title) do
        [
          %LiveToast{
            kind: kind,
            msg: msg,
            title: title,
            icon: default_icon_for_kind(kind),
            uuid: stable_toast_uuid(kind, msg, title),
            sync: true,
            duration: 6000
          }
        ]
      else
        []
      end
    end)
  end

  defp normalize_flash_keys(flash) do
    Enum.reduce(flash, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, to_string(k), v)
      {k, v}, acc -> Map.put(acc, k, v)
    end)
  end

  defp stable_toast_uuid(kind, msg, title) do
    "redirect-#{kind}-#{:erlang.phash2({kind, msg, title})}"
  end

  defp default_icon_for_kind(:info),
    do: &YscWeb.CoreComponents.flash_toast_icon_success/1

  defp default_icon_for_kind(:error),
    do: &YscWeb.CoreComponents.flash_toast_icon_error/1

  defp default_icon_for_kind(:warning),
    do: &YscWeb.CoreComponents.flash_toast_icon_warning/1

  @doc """
  Toast container classes with z-[10000] so toasts render above modals (z-50)
  and mobile menu overlays (z-[9999]).
  """
  def toast_group_class_fn(assigns) do
    [
      # base: fixed + toast-container-above-all (z-index in app.css) so toasts sit above nav, modals, overlays
      "fixed toast-container-above-all max-h-screen w-full p-4 md:max-w-[420px] pointer-events-none grid origin-center",
      assigns[:corner] == :bottom_left &&
        "items-end bottom-0 left-0 flex-col-reverse sm:top-auto",
      assigns[:corner] == :bottom_center &&
        "items-end bottom-0 left-1/2 transform -translate-x-1/2 flex-col-reverse sm:top-auto",
      assigns[:corner] == :bottom_right &&
        "items-end bottom-0 right-0 flex-col-reverse sm:top-auto",
      assigns[:corner] == :top_left &&
        "items-start top-0 left-0 flex-col sm:bottom-auto",
      assigns[:corner] == :top_center &&
        "items-start top-0 left-1/2 transform -translate-x-1/2 flex-col sm:bottom-auto",
      assigns[:corner] == :top_right &&
        "items-start top-0 right-0 flex-col sm:bottom-auto"
    ]
  end

  def fullscreen?(conn_or_path) when is_binary(conn_or_path) do
    String.starts_with?(conn_or_path, [
      "/users/log-in",
      "/users/register",
      "/users/reset-password",
      "/users/settings/confirm-email",
      "/users/log-in/auto",
      "/account/setup",
      "/onboarding",
      "/report-conduct-violation"
    ])
  end

  def fullscreen?(%Plug.Conn{} = conn) do
    current_path = Path.join(["/" | conn.path_info])
    fullscreen?(current_path)
  end

  def fullscreen?(_), do: false

  def hero_mode?(conn_or_path, current_user) when is_binary(conn_or_path) do
    cond do
      # Home page with no user logged in
      conn_or_path == "/" && current_user == nil ->
        true

      # Booking pages (both logged in and not logged in)
      String.starts_with?(conn_or_path, "/bookings/tahoe") ->
        true

      String.starts_with?(conn_or_path, "/bookings/clear-lake") ->
        true

      true ->
        false
    end
  end

  def hero_mode?(%Plug.Conn{} = conn, current_user) do
    current_path = Path.join(["/" | conn.path_info])
    hero_mode?(current_path, current_user)
  end

  def hero_mode?(_, _), do: false

  attr :current_user, :any, default: nil
  attr :active_membership?, :boolean, default: false
  attr :is_fullscreen, :boolean, default: false

  @doc """
  Pending-approval and inactive-membership alert banners shown in the app layout.
  """
  def membership_status_banners(assigns) do
    ~H"""
    <.alert_banner
      :if={
        @current_user && @current_user.state == :pending_approval &&
          !@is_fullscreen
      }
      type="warning"
      icon="hero-exclamation-triangle"
      title="Application Under Review"
    >
      Our board is reviewing your membership application. We will email you when there is a decision. Cabin bookings, event tickets, and other member benefits are available after the board approves you and your membership dues are paid. For timelines and optional early payment setup, <.link
        navigate={~p"/pending-review"}
        class="hover:underline font-bold"
      >view your application status</.link>.
    </.alert_banner>

    <.alert_banner
      :if={
        @current_user && @current_user.state == :active && !@active_membership? &&
          !@is_fullscreen
      }
      type="orange"
      icon="hero-exclamation-triangle"
      title="Membership Required"
      action_label="Manage Membership"
      action_path={~p"/users/membership"}
    >
      To access events and the cabin booking system, you need an active, paid membership. Use the
      <strong>Manage Membership</strong>
      button to choose a plan and complete payment.
    </.alert_banner>
    """
  end

  attr :title, :string, required: true

  @doc "Uppercase section heading for the site footer link columns."
  def footer_section_heading(assigns) do
    ~H"""
    <h2 class="mb-4 text-sm font-semibold text-zinc-900 uppercase tracking-wide">
      {@title}
    </h2>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(navigate href target rel aria-label)

  slot :inner_block, required: true

  @doc "Footer column link with shared underline styling."
  def footer_nav_link(assigns) do
    ~H"""
    <.link
      {@rest}
      class={[
        "underline underline-offset-4 decoration-zinc-300 hover:decoration-zinc-600 hover:text-zinc-900 transition-colors",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
