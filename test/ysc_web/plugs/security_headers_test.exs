defmodule YscWeb.Plugs.SecurityHeadersTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias YscWeb.Plugs.SecurityHeaders

  setup do
    # Preserve config we mutate
    old_env = Application.get_env(:ysc, :environment)
    old_endpoint = Application.get_env(:ysc, YscWeb.Endpoint)

    on_exit(fn ->
      if is_nil(old_env),
        do: Application.delete_env(:ysc, :environment),
        else: Application.put_env(:ysc, :environment, old_env)

      if is_nil(old_endpoint),
        do: Application.delete_env(:ysc, YscWeb.Endpoint),
        else: Application.put_env(:ysc, YscWeb.Endpoint, old_endpoint)
    end)

    :ok
  end

  test "sets CSP header including nonce" do
    Application.put_env(:ysc, :environment, :dev)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: true)

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "abc123")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    assert String.contains?(csp, "'nonce-abc123'")
    assert String.contains?(csp, "script-src")
    assert String.contains?(csp, "connect-src")
    assert String.contains?(csp, "img-src")
  end

  test "adds HSTS header only in production and only for https" do
    # production (anything other than :dev) + https
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)

    https_conn =
      conn(:get, "/")
      |> Map.put(:scheme, :https)
      |> SecurityHeaders.call([])

    assert get_resp_header(https_conn, "strict-transport-security") != []

    http_conn =
      conn(:get, "/")
      |> Map.put(:scheme, :http)
      |> SecurityHeaders.call([])

    assert get_resp_header(http_conn, "strict-transport-security") == []
  end

  test "in production, CSP includes upgrade-insecure-requests" do
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "n")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    assert String.contains?(csp, "upgrade-insecure-requests")
  end

  test "in dev, CSP does not include upgrade-insecure-requests" do
    Application.put_env(:ysc, :environment, :dev)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: true)

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "n")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    refute String.contains?(csp, "upgrade-insecure-requests")
  end
end
