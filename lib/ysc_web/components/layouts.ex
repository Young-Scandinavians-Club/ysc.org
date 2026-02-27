defmodule YscWeb.Layouts do
  use YscWeb, :html

  import LiveToast, only: [toast_group: 1]

  embed_templates "layouts/*"

  @doc """
  Merges toasts_sync with any welcome-back toast and returns {toasts_sync, flash}.
  When a welcome toast is added, :info is removed from flash so Components.flashes
  does not render a duplicate on first paint. The LiveToast patch adds the sync
  toast to the stream even without a matching flash.
  """
  def toasts_sync_with_flash(assigns) do
    base = assigns[:toasts_sync] || []
    flash = assigns[:flash] || %{}
    # Support both string and atom keys (session/redirect may use either)
    info_msg = flash["info"] || flash[:info]

    if info_msg && is_binary(info_msg) &&
         String.contains?(info_msg, "Welcome back") do
      welcome_toast = %LiveToast{
        kind: :info,
        msg: info_msg,
        title: "Welcome back! 👋",
        icon: &YscWeb.CoreComponents.flash_toast_icon_success/1,
        uuid: Ecto.UUID.generate(),
        sync: true
      }

      # Strip both key forms so Components.flashes does not show a second toast
      flash_for_toast = flash |> Map.delete("info") |> Map.delete(:info)
      {[welcome_toast | base], flash_for_toast}
    else
      {base, flash}
    end
  end

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
end
