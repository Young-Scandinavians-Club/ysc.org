defmodule YscWeb.OAuthControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.OAuth
  alias Ysc.OAuth.AuthCode
  alias Ysc.Repo

  @client_id "query_console_test"
  @client_secret "test_secret_change_me"
  @redirect_uri "http://localhost:4001/auth/ysc/callback"
  @post_logout_redirect_uri "http://localhost:4001/auth/signed-out"
  @code_verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

  setup do
    code_challenge = pkce_challenge(@code_verifier)
    %{code_challenge: code_challenge}
  end

  describe "GET /oauth/authorize" do
    test "redirects unauthenticated users to login with return_to", %{
      conn: conn,
      code_challenge: code_challenge
    } do
      conn = get(conn, authorize_path(code_challenge))

      assert redirected_to(conn) == ~p"/users/log-in"

      assert get_session(conn, :user_return_to) =~
               "/oauth/authorize"
    end

    test "returns 403 for non-admin members", %{
      conn: conn,
      code_challenge: code_challenge
    } do
      user = user_fixture(%{role: :member, state: :active})
      conn = conn |> log_in_user(user) |> get(authorize_path(code_challenge))

      assert response(conn, 403) =~ "Forbidden"
    end

    test "returns 403 for volunteers", %{
      conn: conn,
      code_challenge: code_challenge
    } do
      user = user_fixture(%{role: :volunteer, state: :active})
      conn = conn |> log_in_user(user) |> get(authorize_path(code_challenge))

      assert response(conn, 403) =~ "Forbidden"
    end

    test "returns 400 for invalid redirect_uri", %{
      conn: conn,
      code_challenge: code_challenge
    } do
      admin = user_fixture(%{role: :admin, state: :active})

      conn =
        conn
        |> log_in_user(admin)
        |> get(
          authorize_path(code_challenge,
            redirect_uri: "https://evil.example/callback"
          )
        )

      assert response(conn, 400) =~ "Invalid redirect_uri"
    end

    test "redirects with code and state for active admin", %{
      conn: conn,
      code_challenge: code_challenge
    } do
      admin =
        user_fixture(%{
          role: :admin,
          state: :active,
          first_name: "Ada",
          last_name: "Admin"
        })

      state = "csrf-state-123"

      conn =
        conn
        |> log_in_user(admin)
        |> get(authorize_path(code_challenge, state: state))

      assert redirected_to(conn, 302) =~ @redirect_uri

      uri = URI.parse(redirected_to(conn))
      query = URI.decode_query(uri.query)
      assert query["state"] == state
      assert is_binary(query["code"]) and query["code"] != ""
    end

    test "uses real admin when impersonating", %{
      conn: conn,
      code_challenge: code_challenge
    } do
      admin = user_fixture(%{role: :admin, state: :active})
      member = user_fixture(%{role: :member, state: :active})

      conn =
        conn
        |> log_in_user(admin)
        |> put_session(:impersonated_user_id, member.id)
        |> get(authorize_path(code_challenge))

      assert redirected_to(conn, 302) =~ @redirect_uri

      uri = URI.parse(redirected_to(conn))
      code = URI.decode_query(uri.query)["code"]

      assert {:ok, payload} =
               OAuth.exchange_token(
                 token_params(code),
                 @client_id,
                 @client_secret
               )

      assert payload["user"]["id"] == admin.id
    end
  end

  describe "GET /oauth/logout" do
    test "clears session and redirects to allowlisted post_logout_redirect_uri",
         %{
           conn: conn
         } do
      admin = user_fixture(%{role: :admin, state: :active})

      conn =
        conn
        |> log_in_user(admin)
        |> get(logout_path())

      assert redirected_to(conn, 302) == @post_logout_redirect_uri
      refute get_session(conn, :user_token)
    end

    test "works when already logged out", %{conn: conn} do
      conn = get(conn, logout_path())
      assert redirected_to(conn, 302) == @post_logout_redirect_uri
    end

    test "rejects unknown client_id", %{conn: conn} do
      conn = get(conn, logout_path(client_id: "unknown_client"))
      assert response(conn, 400) =~ "Invalid client_id"
    end

    test "rejects non-allowlisted post_logout_redirect_uri", %{conn: conn} do
      conn =
        get(
          conn,
          logout_path(post_logout_redirect_uri: "https://evil.example/bye")
        )

      assert response(conn, 400) =~ "Invalid post_logout_redirect_uri"
    end
  end

  describe "POST /oauth/token" do
    setup %{conn: conn, code_challenge: code_challenge} do
      admin =
        user_fixture(%{
          role: :admin,
          state: :active,
          first_name: "Ada",
          last_name: "Admin"
        })

      conn = log_in_user(conn, admin)
      authorize_conn = get(conn, authorize_path(code_challenge))
      code = extract_code(authorize_conn)

      %{admin: admin, code: code}
    end

    test "exchanges code for user identity payload", %{
      conn: conn,
      admin: admin,
      code: code
    } do
      conn =
        conn
        |> put_req_header(
          "authorization",
          basic_auth(@client_id, @client_secret)
        )
        |> post(~p"/oauth/token", token_params(code))

      assert %{
               "token_type" => "bearer",
               "expires_in" => 0,
               "user" => user
             } = json_response(conn, 200)

      assert user["id"] == admin.id
      assert user["email"] == admin.email
      assert user["display_name"] == "Ada Admin"
      assert user["role"] == "admin"
      assert user["state"] == "active"
    end

    test "accepts client_secret in body", %{
      conn: conn,
      admin: admin,
      code: code
    } do
      params =
        token_params(code)
        |> Map.put("client_id", @client_id)
        |> Map.put("client_secret", @client_secret)

      conn = post(conn, ~p"/oauth/token", params)

      assert json_response(conn, 200)["user"]["id"] == admin.id
    end

    test "rejects expired code", %{conn: conn, code: code} do
      expire_code!(code)

      conn =
        conn
        |> put_req_header(
          "authorization",
          basic_auth(@client_id, @client_secret)
        )
        |> post(~p"/oauth/token", token_params(code))

      assert %{"error" => "invalid_grant"} = json_response(conn, 400)
    end

    test "rejects replay of consumed code", %{conn: conn, code: code} do
      auth = basic_auth(@client_id, @client_secret)
      secret_key_base = conn.secret_key_base

      assert json_response(
               conn
               |> put_req_header("authorization", auth)
               |> post(~p"/oauth/token", token_params(code)),
               200
             )

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:secret_key_base, secret_key_base)
        |> put_req_header("authorization", auth)
        |> post(~p"/oauth/token", token_params(code))

      assert %{"error" => "invalid_grant"} = json_response(conn, 400)
    end

    test "rejects PKCE failure", %{conn: conn, code: code} do
      params =
        Map.put(
          token_params(code),
          "code_verifier",
          "wrong-verifier-value-xxxxxx"
        )

      conn =
        conn
        |> put_req_header(
          "authorization",
          basic_auth(@client_id, @client_secret)
        )
        |> post(~p"/oauth/token", params)

      assert %{"error" => "invalid_grant"} = json_response(conn, 400)
    end

    test "rejects bad client secret", %{conn: conn, code: code} do
      conn =
        conn
        |> put_req_header(
          "authorization",
          basic_auth(@client_id, "wrong_secret")
        )
        |> post(~p"/oauth/token", token_params(code))

      assert %{"error" => "invalid_client"} = json_response(conn, 401)
    end
  end

  defp authorize_path(code_challenge, opts \\ []) do
    params = %{
      "client_id" => Keyword.get(opts, :client_id, @client_id),
      "redirect_uri" => Keyword.get(opts, :redirect_uri, @redirect_uri),
      "response_type" => "code",
      "state" => Keyword.get(opts, :state, "test-state"),
      "code_challenge" => code_challenge,
      "code_challenge_method" => "S256"
    }

    ~p"/oauth/authorize?#{params}"
  end

  defp logout_path(opts \\ []) do
    params = %{
      "client_id" => Keyword.get(opts, :client_id, @client_id),
      "post_logout_redirect_uri" =>
        Keyword.get(opts, :post_logout_redirect_uri, @post_logout_redirect_uri)
    }

    ~p"/oauth/logout?#{params}"
  end

  defp token_params(code) do
    %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => @redirect_uri,
      "client_id" => @client_id,
      "code_verifier" => @code_verifier
    }
  end

  defp extract_code(conn) do
    conn
    |> redirected_to(302)
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.fetch!("code")
  end

  defp expire_code!(raw_code) do
    {:ok, decoded} = Base.url_decode64(raw_code, padding: false)
    hashed = :crypto.hash(:sha256, decoded)

    auth_code = Repo.get_by!(AuthCode, hashed_code: hashed)

    past =
      DateTime.utc_now()
      |> DateTime.add(-120, :second)
      |> DateTime.truncate(:second)

    auth_code
    |> Ecto.Changeset.change(%{expires_at: past})
    |> Repo.update!()
  end

  defp pkce_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  defp basic_auth(id, secret) do
    "Basic " <> Base.encode64("#{id}:#{secret}")
  end
end
