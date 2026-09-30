defmodule QueryConsole.ReqUpgradeTest do
  @moduledoc """
  Guards the req 0.7.1 → 0.7.4 upgrade.

  0.7.4 is a patch: `put_params` overwrites existing query keys but keeps
  explicit duplicates, and redirects drop `:path_params` so the Location
  path is not rewritten. 0.7.3 reverts GET-with-body rewriting to POST.
  0.7.2 restores `form_multipart: [{string_name, value}]` and fixes AWS
  SigV4 for Supabase Storage. Query Console only calls `Req.post/2` with
  `json:` for SSO token exchange; we do not pass `:params`,
  `:path_params`, `:form_multipart`, or AWS options. No Elixir API
  breaks for that usage.
  """
  use ExUnit.Case, async: true

  alias QueryConsole.ReqUpgradeTest.ParamsStub
  alias QueryConsole.ReqUpgradeTest.RedirectStub
  alias QueryConsole.ReqUpgradeTest.TokenStub

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/req/CHANGELOG.md", __DIR__)
  @sso_src Path.expand("../../lib/query_console/sso.ex", __DIR__)
  @steps_src Path.expand("../../deps/req/lib/req/steps.ex", __DIR__)

  setup context do
    Req.Test.set_req_test_from_context(context)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:req)
    {:module, Req} = Code.ensure_loaded(Req)
    {:module, Req.Response} = Code.ensure_loaded(Req.Response)
    {:module, Req.Test} = Code.ensure_loaded(Req.Test)
    {:module, Req.Steps} = Code.ensure_loaded(Req.Steps)
    :ok
  end

  describe "0.7.4 Hex lock and public APIs" do
    test "locks the Hex package to 0.7.4" do
      assert to_string(Application.spec(:req, :vsn)) == "0.7.4"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:req, "~> 0.7.4"})
    end

    test "companion lock is 0.7.4 and finch stays 0.23.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"req": {:hex, :req, "0.7.4"|
      assert lock =~ ~s|"finch": {:hex, :finch, "0.23.0"|
    end

    test "get, post, request, and Test modules we use still load" do
      assert function_exported?(Req, :get, 1)
      assert function_exported?(Req, :get, 2)
      assert function_exported?(Req, :post, 2)
      assert function_exported?(Req, :request, 1)
      assert function_exported?(Req.Test, :stub, 2)
      assert function_exported?(Req.Test, :json, 2)
    end

    test "SSO still exchanges tokens with Req.post json, not params" do
      sso = File.read!(@sso_src)
      assert sso =~ "Req.post(conf.token_url, json: body)"
      refute sso =~ "path_params:"
      refute sso =~ "form_multipart:"
      refute sso =~ ~r/Req\.(get|post|request)\([^)]*\bparams:/
    end
  end

  describe "0.7.4 changelog" do
    test "documents put_params duplicates, redirect path_params, and 0.7.3 GET revert" do
      changelog = File.read!(@changelog)
      assert changelog =~ "Allow explicit duplicates"
      assert changelog =~ "Do not overwrite redirect target"
      assert changelog =~ ~s|Revert "Automatically change GET to POST when request body is set."|
    end
  end

  describe "SSO-style Req.post json token exchange" do
    test "posts JSON and returns a 200 map body" do
      Req.Test.stub(TokenStub, fn conn ->
        assert conn.method == "POST"

        Req.Test.json(conn, %{
          "user" => %{
            "id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV",
            "email" => "admin@ysc.org",
            "display_name" => "Admin",
            "role" => "admin",
            "state" => "active"
          }
        })
      end)

      body = %{
        grant_type: "authorization_code",
        code: "auth-code",
        redirect_uri: "http://localhost:4001/auth/ysc/callback",
        client_id: "query_console_test",
        client_secret: "test_secret_change_me",
        code_verifier: "verifier"
      }

      assert {:ok, %{status: 200, body: claims}} =
               Req.post("http://localhost:4000/oauth/token",
                 json: body,
                 plug: {Req.Test, TokenStub}
               )

      assert is_map(claims)
      assert claims["user"]["email"] == "admin@ysc.org"
    end
  end

  describe "0.7.4 put_params" do
    test "overwrites existing query keys but keeps explicit duplicates" do
      Req.Test.stub(ParamsStub, fn conn ->
        Plug.Conn.send_resp(conn, 200, conn.query_string)
      end)

      assert {:ok, %{status: 200, body: body}} =
               Req.get("http://example.com/?id=1&foo=bar",
                 params: [id: 2, id: 3],
                 plug: {Req.Test, ParamsStub}
               )

      assert body == "id=2&id=3&foo=bar"
    end

    test "does not append when a single replacement value is given" do
      request =
        Req.new(url: "https://example.com/?id=1&foo=bar", params: [id: 2])
        |> Req.Steps.put_params()

      assert request.url.query == "id=2&foo=bar"
    end
  end

  describe "0.7.4 put_path_params on redirect" do
    test "does not rewrite the Location path with leftover path_params" do
      Req.Test.stub(RedirectStub, fn conn ->
        case conn.request_path do
          "/items/abc" ->
            conn
            |> Plug.Conn.put_resp_header("location", "/items/abc/done")
            |> Plug.Conn.send_resp(302, "")

          "/items/abc/done" ->
            Plug.Conn.send_resp(conn, 200, "arrived")

          other ->
            Plug.Conn.send_resp(conn, 500, "unexpected #{other}")
        end
      end)

      assert {:ok, %{status: 200, body: "arrived"}} =
               Req.get("http://example.com/items/:id",
                 path_params: [id: "abc"],
                 plug: {Req.Test, RedirectStub}
               )
    end

    test "redirect step deletes path_params before following Location" do
      source = File.read!(@steps_src)
      assert source =~ "|> Req.Request.delete_option(:params)"
      assert source =~ "|> Req.Request.delete_option(:path_params)"
    end
  end

  describe "0.7.3 GET-with-body still holds" do
    test "explicit GET with a body is not rewritten to POST" do
      Req.Test.stub(ParamsStub, fn conn ->
        Plug.Conn.send_resp(conn, 200, conn.method)
      end)

      assert {:ok, %{status: 200, body: "GET"}} =
               Req.request(
                 method: :get,
                 url: "http://example.com/v1/list",
                 body: "limit=1",
                 plug: {Req.Test, ParamsStub}
               )
    end
  end
end
