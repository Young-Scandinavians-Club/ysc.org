defmodule YscWeb.Plugs.SiteSettingsPlugs do
  @moduledoc """
  Plug for mounting site settings in LiveView.

  Loads and makes site settings available in LiveView socket assigns.
  """
  use YscWeb, :verified_routes

  import Plug.Conn

  alias Ysc.Settings

  def on_mount(:mount_site_settings, _params, _session, socket) do
    {:cont, mount_site_settings(socket)}
  end

  def mount_site_settings(conn, _opts) do
    assign(
      conn,
      :site_setting_socials_instagram,
      Settings.get_social_url("instagram")
    )
    |> assign(
      :site_setting_socials_facebook,
      Settings.get_social_url("facebook")
    )
    |> assign(
      :site_setting_socials_partiful,
      Settings.get_social_url("partiful")
    )
    |> assign(
      :site_setting_socials_whatsapp,
      Settings.get_social_url("whatsapp")
    )
  end

  defp mount_site_settings(socket) do
    Phoenix.Component.assign_new(socket, :site_setting_socials_instagram, fn ->
      Settings.get_social_url("instagram")
    end)
    |> Phoenix.Component.assign_new(:site_setting_socials_facebook, fn ->
      Settings.get_social_url("facebook")
    end)
    |> Phoenix.Component.assign_new(:site_setting_socials_partiful, fn ->
      Settings.get_social_url("partiful")
    end)
    |> Phoenix.Component.assign_new(:site_setting_socials_whatsapp, fn ->
      Settings.get_social_url("whatsapp")
    end)
  end
end
