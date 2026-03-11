defmodule YscWeb.Layouts do
  use YscWeb, :html

  import LiveToast, only: [toast_group: 1]

  embed_templates "layouts/*"

  @doc """
  Builds toasts_sync and flash for the toast group. Promotes flash messages that
  have a custom title (from redirects via YscWeb.Flash) into full toasts with
  title and icon. Welcome-back message gets a dedicated title and icon.
  Uses stable UUIDs for promoted toasts so re-renders don't duplicate.
  """
  def toasts_sync_with_flash(assigns) do
    base = assigns[:toasts_sync] || []
    flash = assigns[:flash] || %{}
    flash = normalize_flash_keys(flash)

    info_msg = flash["info"]

    {toasts_sync, flash} =
      if info_msg && is_binary(info_msg) &&
           String.contains?(info_msg, "Welcome back") do
        {[welcome_toast(info_msg) | base], Map.delete(flash, "info")}
      else
        promoted = promote_flash_to_toasts(flash)
        {promoted ++ base, strip_promoted_keys(flash, promoted)}
      end

    {toasts_sync, flash}
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

  defp strip_promoted_keys(flash, []), do: flash

  defp strip_promoted_keys(flash, promoted) do
    Enum.reduce(promoted, flash, fn %LiveToast{kind: kind}, acc ->
      key = to_string(kind)

      acc
      |> Map.delete(key)
      |> Map.delete("#{key}_toast_title")
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
