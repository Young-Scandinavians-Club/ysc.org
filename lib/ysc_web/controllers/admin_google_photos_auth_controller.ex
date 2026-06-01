defmodule YscWeb.AdminGooglePhotosAuthController do
  @moduledoc """
  Admin-only OAuth flow for connecting the organization's Google Photos account.
  """
  use YscWeb, :controller

  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.OAuth

  @session_state_key :google_photos_oauth_state

  def connect(conn, _params) do
    if OAuth.configured?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      authorize_url =
        case OAuth.authorize_url(state) do
          url when is_binary(url) -> url
          {:error, _} -> nil
        end

      if authorize_url do
        conn
        |> put_session(@session_state_key, state)
        |> redirect(external: authorize_url)
      else
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Google Photos OAuth is not fully configured.",
          title: "Google Photos"
        )
        |> redirect(to: settings_path())
      end
    else
      conn
      |> YscWeb.Flash.put_toast(
        :error,
        "Set GOOGLE_PHOTOS_CLIENT_ID and GOOGLE_PHOTOS_CLIENT_SECRET to enable Google Photos.",
        title: "Google Photos"
      )
      |> redirect(to: settings_path())
    end
  end

  def callback(conn, params) do
    session_state = get_session(conn, @session_state_key)
    conn = delete_session(conn, @session_state_key)

    cond do
      params["error"] ->
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Google authorization was cancelled or denied.",
          title: "Google Photos"
        )
        |> redirect(to: settings_path())

      not valid_state?(session_state, params["state"]) ->
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Invalid OAuth state. Please try connecting again.",
          title: "Google Photos"
        )
        |> redirect(to: settings_path())

      not is_binary(params["code"]) ->
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Missing authorization code from Google.",
          title: "Google Photos"
        )
        |> redirect(to: settings_path())

      true ->
        handle_successful_callback(conn, params["code"])
    end
  end

  def disconnect(conn, _params) do
    GooglePhotos.disconnect!()

    conn
    |> YscWeb.Flash.put_toast(:info, "Google Photos disconnected.",
      title: "Google Photos"
    )
    |> redirect(to: settings_path())
  end

  defp handle_successful_callback(conn, code) do
    user = conn.assigns.current_user

    with {:ok, token_map} <- OAuth.exchange_code(code),
         {:ok, email} <- OAuth.fetch_userinfo(token_map.access_token) do
      GooglePhotos.connect!(token_map, user.id, email)

      conn
      |> YscWeb.Flash.put_toast(
        :info,
        "Google Photos connected as #{email}.",
        title: "Google Photos"
      )
      |> redirect(to: settings_path())
    else
      {:error, {:token_error, _status}} ->
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Google rejected the authorization code. Try connecting again.",
          title: "Google Photos"
        )
        |> redirect(to: settings_path())

      {:error, _} ->
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Failed to connect Google Photos. Please try again.",
          title: "Google Photos"
        )
        |> redirect(to: settings_path())
    end
  end

  defp valid_state?(session_state, state)
       when is_binary(session_state) and is_binary(state) do
    Plug.Crypto.secure_compare(session_state, state)
  end

  defp valid_state?(_, _), do: false

  defp settings_path, do: ~p"/admin/settings"
end
