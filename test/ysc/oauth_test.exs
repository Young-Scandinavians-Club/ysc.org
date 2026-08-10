defmodule Ysc.OAuthTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.OAuth
  alias Ysc.Repo

  @client_id "query_console_test"
  @client_secret "test_secret_change_me"
  @redirect_uri "http://localhost:4001/auth/ysc/callback"
  @post_logout_redirect_uri "http://localhost:4001/auth/signed-out"
  @code_verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

  defp code_challenge do
    :crypto.hash(:sha256, @code_verifier)
    |> Base.url_encode64(padding: false)
  end

  defp authorize_params(overrides \\ %{}) do
    %{
      "client_id" => @client_id,
      "redirect_uri" => @redirect_uri,
      "response_type" => "code",
      "state" => "test-state",
      "code_challenge" => code_challenge(),
      "code_challenge_method" => "S256"
    }
    |> Map.merge(overrides)
  end

  defp token_params(code, overrides \\ %{}) do
    %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => @redirect_uri,
      "client_id" => @client_id,
      "code_verifier" => @code_verifier
    }
    |> Map.merge(overrides)
  end

  defp admin_fixture(attrs \\ %{}) do
    user_fixture(Map.merge(%{role: :admin, state: :active}, attrs))
  end

  defp authorize_code!(user, overrides \\ %{}) do
    {:ok, redirect_url} =
      OAuth.create_authorization(user, authorize_params(overrides))

    redirect_url
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.fetch!("code")
  end

  describe "client/1" do
    test "returns nil for a non-binary argument" do
      assert OAuth.client(nil) == nil
      assert OAuth.client(123) == nil
    end

    test "returns the registered client config for a known client_id" do
      assert %{client_secret: @client_secret} = OAuth.client(@client_id)
    end

    test "returns nil for an unregistered client_id" do
      assert OAuth.client("unknown_client") == nil
    end
  end

  describe "code_ttl_seconds/0" do
    test "returns the configured code lifetime" do
      assert OAuth.code_ttl_seconds() == 60
    end
  end

  describe "create_authorization/2 error paths" do
    test "returns :invalid_client when client_id is missing" do
      admin = admin_fixture()

      assert {:error, :invalid_client} =
               OAuth.create_authorization(
                 admin,
                 Map.delete(authorize_params(), "client_id")
               )
    end

    test "returns :invalid_client for an unregistered client_id" do
      admin = admin_fixture()

      assert {:error, :invalid_client} =
               OAuth.create_authorization(
                 admin,
                 authorize_params(%{"client_id" => "unknown_client"})
               )
    end

    test "returns :not_eligible for a non-admin role" do
      member = user_fixture(%{role: :member, state: :active})

      assert {:error, :not_eligible} =
               OAuth.create_authorization(member, authorize_params())
    end

    test "returns :invalid_redirect_uri when redirect_uri is missing" do
      admin = admin_fixture()

      assert {:error, :invalid_redirect_uri} =
               OAuth.create_authorization(
                 admin,
                 Map.delete(authorize_params(), "redirect_uri")
               )
    end

    test "returns :invalid_redirect_uri when redirect_uri is not allowlisted" do
      admin = admin_fixture()

      assert {:error, :invalid_redirect_uri} =
               OAuth.create_authorization(
                 admin,
                 authorize_params(%{"redirect_uri" => "https://evil.example/cb"})
               )
    end

    test "returns :unsupported_response_type when response_type is missing" do
      admin = admin_fixture()

      assert {:error, :unsupported_response_type} =
               OAuth.create_authorization(
                 admin,
                 Map.delete(authorize_params(), "response_type")
               )
    end

    test "returns :unsupported_response_type for response_type other than code" do
      admin = admin_fixture()

      assert {:error, :unsupported_response_type} =
               OAuth.create_authorization(
                 admin,
                 authorize_params(%{"response_type" => "token"})
               )
    end

    test "returns :missing_state when state is absent" do
      admin = admin_fixture()

      assert {:error, :missing_state} =
               OAuth.create_authorization(
                 admin,
                 Map.delete(authorize_params(), "state")
               )
    end

    test "returns :missing_state when state is blank" do
      admin = admin_fixture()

      assert {:error, :missing_state} =
               OAuth.create_authorization(
                 admin,
                 authorize_params(%{"state" => ""})
               )
    end

    test "returns :invalid_pkce when code_challenge is missing" do
      admin = admin_fixture()

      assert {:error, :invalid_pkce} =
               OAuth.create_authorization(
                 admin,
                 Map.delete(authorize_params(), "code_challenge")
               )
    end

    test "returns :invalid_pkce when code_challenge_method is not S256" do
      admin = admin_fixture()

      assert {:error, :invalid_pkce} =
               OAuth.create_authorization(
                 admin,
                 authorize_params(%{"code_challenge_method" => "plain"})
               )
    end

    test "succeeds and creates a one-time code for an eligible admin" do
      admin = admin_fixture()

      assert {:ok, redirect_url} =
               OAuth.create_authorization(admin, authorize_params())

      assert redirect_url =~ @redirect_uri
    end
  end

  describe "validate_logout_request/1" do
    test "returns :invalid_client when client_id is unknown" do
      assert {:error, :invalid_client} =
               OAuth.validate_logout_request(%{"client_id" => "unknown_client"})
    end

    test "returns :invalid_client when client_id is missing" do
      assert {:error, :invalid_client} = OAuth.validate_logout_request(%{})
    end

    test "returns :invalid_redirect_uri when post_logout_redirect_uri is missing" do
      assert {:error, :invalid_redirect_uri} =
               OAuth.validate_logout_request(%{"client_id" => @client_id})
    end

    test "returns :invalid_redirect_uri when post_logout_redirect_uri is blank" do
      assert {:error, :invalid_redirect_uri} =
               OAuth.validate_logout_request(%{
                 "client_id" => @client_id,
                 "post_logout_redirect_uri" => ""
               })
    end

    test "returns :invalid_redirect_uri when not allowlisted" do
      assert {:error, :invalid_redirect_uri} =
               OAuth.validate_logout_request(%{
                 "client_id" => @client_id,
                 "post_logout_redirect_uri" => "https://evil.example/bye"
               })
    end

    test "succeeds for an allowlisted post_logout_redirect_uri" do
      assert {:ok, @post_logout_redirect_uri} =
               OAuth.validate_logout_request(%{
                 "client_id" => @client_id,
                 "post_logout_redirect_uri" => @post_logout_redirect_uri
               })
    end

    test "falls back to string-keyed client config for post_logout_redirect_uris" do
      original = Application.get_env(:ysc, :oauth_clients, %{})

      string_keyed_client = %{
        "post_logout_redirect_uris" => ["http://localhost:9999/bye"],
        client_secret: "string_keyed_secret",
        redirect_uris: ["http://localhost:9999/cb"]
      }

      Application.put_env(
        :ysc,
        :oauth_clients,
        Map.put(original, "string_keyed_client", string_keyed_client)
      )

      on_exit(fn -> Application.put_env(:ysc, :oauth_clients, original) end)

      assert {:ok, "http://localhost:9999/bye"} =
               OAuth.validate_logout_request(%{
                 "client_id" => "string_keyed_client",
                 "post_logout_redirect_uri" => "http://localhost:9999/bye"
               })
    end
  end

  describe "exchange_token/3 error paths" do
    setup do
      admin = admin_fixture(%{first_name: "Ada", last_name: "Admin"})
      code = authorize_code!(admin)
      %{admin: admin, code: code}
    end

    test "returns :invalid_client when no credentials are supplied at all", %{
      code: code
    } do
      assert {:error, :invalid_client} =
               OAuth.exchange_token(
                 token_params(code, %{"client_id" => nil, "client_secret" => nil}),
                 nil,
                 nil
               )
    end

    test "returns :invalid_client for unregistered client credentials", %{
      code: code
    } do
      assert {:error, :invalid_client} =
               OAuth.exchange_token(
                 token_params(code, %{"client_id" => "unknown_client"}),
                 "unknown_client",
                 "whatever"
               )
    end

    test "returns :invalid_client for a wrong client secret", %{code: code} do
      assert {:error, :invalid_client} =
               OAuth.exchange_token(token_params(code), @client_id, "wrong")
    end

    test "returns :unsupported_grant_type when grant_type is missing", %{
      code: code
    } do
      params = Map.delete(token_params(code), "grant_type")

      assert {:error, :unsupported_grant_type} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :unsupported_grant_type for an unexpected grant_type", %{
      code: code
    } do
      params = token_params(code, %{"grant_type" => "client_credentials"})

      assert {:error, :unsupported_grant_type} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :invalid_request when code is missing" do
      params = %{
        "grant_type" => "authorization_code",
        "redirect_uri" => @redirect_uri,
        "code_verifier" => @code_verifier
      }

      assert {:error, :invalid_request} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :invalid_request when redirect_uri is missing", %{code: code} do
      params = Map.delete(token_params(code), "redirect_uri")

      assert {:error, :invalid_request} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :invalid_request when code_verifier is missing", %{
      code: code
    } do
      params = Map.delete(token_params(code), "code_verifier")

      assert {:error, :invalid_request} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :invalid_client when body client_id mismatches the authenticated client",
         %{code: code} do
      params = token_params(code, %{"client_id" => "unknown_client"})

      assert {:error, :invalid_client} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "succeeds when body has no client_id at all (basic auth only)", %{
      admin: admin,
      code: code
    } do
      params = Map.delete(token_params(code), "client_id")

      assert {:ok, payload} =
               OAuth.exchange_token(params, @client_id, @client_secret)

      assert payload["user"]["id"] == admin.id
    end

    test "returns :invalid_grant for an undecodable (non-base64) code" do
      params = token_params("not!!valid==base64")

      assert {:error, :invalid_grant} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :invalid_grant for a well-formed but unknown code" do
      bogus_code = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      params = token_params(bogus_code)

      assert {:error, :invalid_grant} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :invalid_grant when redirect_uri does not match the authorized one",
         %{code: code} do
      params = token_params(code, %{"redirect_uri" => "http://localhost:4001/other"})

      assert {:error, :invalid_grant} =
               OAuth.exchange_token(params, @client_id, @client_secret)
    end

    test "returns :invalid_grant when the authorizing client_id no longer matches",
         %{code: code} do
      original = Application.get_env(:ysc, :oauth_clients, %{})

      other_client = %{
        client_secret: "other_secret",
        redirect_uris: [@redirect_uri],
        roles: [:admin],
        states: [:active]
      }

      Application.put_env(
        :ysc,
        :oauth_clients,
        Map.put(original, "other_client", other_client)
      )

      on_exit(fn -> Application.put_env(:ysc, :oauth_clients, original) end)

      params = token_params(code, %{"client_id" => "other_client"})

      assert {:error, :invalid_grant} =
               OAuth.exchange_token(params, "other_client", "other_secret")
    end

    test "returns :invalid_grant when the user became ineligible after the code was issued",
         %{admin: admin, code: code} do
      admin
      |> Ecto.Changeset.change(%{role: :member})
      |> Repo.update!()

      assert {:error, :invalid_grant} =
               OAuth.exchange_token(token_params(code), @client_id, @client_secret)
    end

    test "falls back to 'Unknown' display name when the user has no name on file",
         %{admin: admin, code: code} do
      admin
      |> Ecto.Changeset.change(%{first_name: "", last_name: ""})
      |> Repo.update!()

      assert {:ok, payload} =
               OAuth.exchange_token(token_params(code), @client_id, @client_secret)

      assert payload["user"]["display_name"] == "Unknown"
    end
  end

  describe "ci_query_explain_query/0" do
    test "builds a runnable Ecto query for CI query-plan diagnostics" do
      query = OAuth.ci_query_explain_query()

      assert %Ecto.Query{} = query
      assert Repo.all(query) == []
    end
  end
end
