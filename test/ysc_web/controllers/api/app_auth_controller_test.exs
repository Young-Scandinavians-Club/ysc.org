defmodule YscWeb.Api.AppAuthControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's sign-in and sign-out endpoints
  (`AppAuthController` + `AppAuthJSON`).
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "POST /api/v1/app/auth/password" do
    test "returns a bearer token for a valid admin", %{conn: conn} do
      user = user_fixture(%{role: :admin})

      response =
        post(conn, ~p"/api/v1/app/auth/password", %{
          "email" => user.email,
          "password" => valid_user_password()
        })

      assert %{"token" => token, "user" => user_json} =
               json_response(response, 200)

      assert is_binary(token) and token != ""
      assert user_json["id"] == to_string(user.id)
      assert user_json["role"] == "admin"

      assert is_binary(user_json["avatar_url"]) and
               user_json["avatar_url"] != ""

      assert Accounts.get_user_by_mobile_token(token).id == user.id
    end

    test "returns a bearer token for a valid volunteer", %{conn: conn} do
      user = user_fixture(%{role: :volunteer})

      response =
        post(conn, ~p"/api/v1/app/auth/password", %{
          "email" => user.email,
          "password" => valid_user_password()
        })

      assert %{"token" => _token} = json_response(response, 200)
    end

    test "rejects a plain member even with correct credentials", %{conn: conn} do
      user = user_fixture(%{role: :member})

      response =
        post(conn, ~p"/api/v1/app/auth/password", %{
          "email" => user.email,
          "password" => valid_user_password()
        })

      assert json_response(response, 401)
    end

    test "rejects an incorrect password", %{conn: conn} do
      user = user_fixture(%{role: :admin})

      response =
        post(conn, ~p"/api/v1/app/auth/password", %{
          "email" => user.email,
          "password" => "wrong password"
        })

      assert json_response(response, 401)
    end

    test "rejects an unknown email", %{conn: conn} do
      response =
        post(conn, ~p"/api/v1/app/auth/password", %{
          "email" => unique_user_email(),
          "password" => "whatever password"
        })

      assert json_response(response, 401)
    end

    test "returns 400 when email or password is missing", %{conn: conn} do
      response =
        post(conn, ~p"/api/v1/app/auth/password", %{"email" => "a@b.com"})

      assert json_response(response, 400)
    end
  end

  describe "POST /api/v1/app/auth/exchange" do
    setup do
      verifier = String.duplicate("a", 64)
      challenge = :crypto.hash(:sha256, verifier) |> Base.encode16(case: :lower)
      %{verifier: verifier, challenge: challenge}
    end

    test "exchanges a valid code for a bearer token", %{
      conn: conn,
      verifier: verifier,
      challenge: challenge
    } do
      user = user_fixture(%{role: :admin})
      code = Accounts.generate_mobile_redirect_token(user, challenge)

      response =
        post(conn, ~p"/api/v1/app/auth/exchange", %{
          "code" => code,
          "code_verifier" => verifier
        })

      assert %{"token" => token, "user" => user_json} =
               json_response(response, 200)

      assert is_binary(token) and token != ""
      assert user_json["id"] == to_string(user.id)

      assert Accounts.get_user_by_mobile_token(token).id == user.id
    end

    test "rejects a plain member's code even though it was validly issued", %{
      conn: conn,
      verifier: verifier,
      challenge: challenge
    } do
      user = user_fixture(%{role: :member})
      code = Accounts.generate_mobile_redirect_token(user, challenge)

      response =
        post(conn, ~p"/api/v1/app/auth/exchange", %{
          "code" => code,
          "code_verifier" => verifier
        })

      assert json_response(response, 401)
    end

    test "rejects an unknown code", %{conn: conn, verifier: verifier} do
      response =
        post(conn, ~p"/api/v1/app/auth/exchange", %{
          "code" => "not-a-real-code",
          "code_verifier" => verifier
        })

      assert json_response(response, 401)
    end

    test "rejects a code_verifier that doesn't match the challenge it was issued with",
         %{conn: conn, challenge: challenge} do
      user = user_fixture(%{role: :admin})
      code = Accounts.generate_mobile_redirect_token(user, challenge)

      response =
        post(conn, ~p"/api/v1/app/auth/exchange", %{
          "code" => code,
          "code_verifier" => "wrong-verifier"
        })

      assert json_response(response, 401)
    end

    test "a code cannot be exchanged twice", %{
      conn: conn,
      verifier: verifier,
      challenge: challenge
    } do
      user = user_fixture(%{role: :admin})
      code = Accounts.generate_mobile_redirect_token(user, challenge)

      post(conn, ~p"/api/v1/app/auth/exchange", %{
        "code" => code,
        "code_verifier" => verifier
      })

      response =
        post(conn, ~p"/api/v1/app/auth/exchange", %{
          "code" => code,
          "code_verifier" => verifier
        })

      assert json_response(response, 401)
    end

    test "returns 400 when code or code_verifier is missing", %{conn: conn} do
      response = post(conn, ~p"/api/v1/app/auth/exchange", %{})

      assert json_response(response, 400)
    end
  end

  describe "DELETE /api/v1/app/auth/logout" do
    test "revokes the token", %{conn: conn} do
      user = user_fixture(%{role: :admin})
      token = Accounts.generate_user_mobile_token(user)

      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/api/v1/app/auth/logout")

      assert response(response, 204)
      refute Accounts.get_user_by_mobile_token(token)
    end

    test "is a no-op without a token", %{conn: conn} do
      response = delete(conn, ~p"/api/v1/app/auth/logout")
      assert response(response, 204)
    end
  end
end
