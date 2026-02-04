defmodule YscWeb.UserSessionControllerRateLimitTest do
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  describe "POST /users/log-in identifier rate limiting" do
    setup do
      Application.put_env(:ysc, Ysc.AuthRateLimit,
        ip_limit: 10_000,
        identifier_limit: 2
      )

      on_exit(fn ->
        Application.put_env(:ysc, Ysc.AuthRateLimit,
          ip_limit: 10_000,
          identifier_limit: 10_000
        )
      end)

      :ok
    end

    test "returns 429 when same email exceeds identifier limit", %{conn: conn} do
      email = "rate_limit_test@example.com"
      params = %{"user" => %{"email" => email, "password" => "wrong"}}

      post(conn, ~p"/users/log-in", params)
      post(conn, ~p"/users/log-in", params)

      conn3 = post(conn, ~p"/users/log-in", params)

      assert conn3.status == 429
      assert get_resp_header(conn3, "retry-after") != []
      assert conn3.resp_body =~ "Too many attempts"
    end
  end

  describe "GET /users/log-in/passkey identifier rate limiting" do
    setup do
      Application.put_env(:ysc, Ysc.AuthRateLimit,
        ip_limit: 10_000,
        identifier_limit: 2
      )

      on_exit(fn ->
        Application.put_env(:ysc, Ysc.AuthRateLimit,
          ip_limit: 10_000,
          identifier_limit: 10_000
        )
      end)

      user = user_fixture()
      encoded_user_id = Base.url_encode64(user.id, padding: false)
      %{encoded_user_id: encoded_user_id}
    end

    test "returns 429 when same user_id exceeds identifier limit", %{
      conn: conn,
      encoded_user_id: encoded_user_id
    } do
      get(conn, ~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})
      get(conn, ~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})

      conn3 =
        get(conn, ~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})

      assert conn3.status == 429
      assert get_resp_header(conn3, "retry-after") != []
      assert conn3.resp_body =~ "Too many attempts"
    end
  end
end
