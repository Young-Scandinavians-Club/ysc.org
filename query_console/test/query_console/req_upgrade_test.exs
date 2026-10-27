defmodule QueryConsole.ReqUpgradeTest do
  @moduledoc """
  Guards the req 0.7.4 → 0.7.5 upgrade.

  0.7.5 is a patch. `put_aws_sigv4` deletes generated Authorization and
  `x-amz-*` headers before re-signing a retry so the second attempt is
  not invalid. Redirects on HTTP 303 now change the method to GET
  except HEAD (RFC 9110 See Other). 301/302 still only rewrite POST;
  307/308 still keep the method.

  Query Console only calls `Req.post/2` with `json:` for SSO token
  exchange. We do not pass `:params`, `:path_params`, `:form_multipart`,
  or `:aws_sigv4`. Token exchange expects 200 and does not follow 303.
  Public Elixir APIs are unchanged.
  """
  use ExUnit.Case, async: true

  alias QueryConsole.ReqUpgradeTest.ParamsStub
  alias QueryConsole.ReqUpgradeTest.RedirectStub
  alias QueryConsole.ReqUpgradeTest.SeeOtherStub
  alias QueryConsole.ReqUpgradeTest.SigV4Stub
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

  describe "0.7.5 Hex lock and public APIs" do
    test "locks the Hex package to 0.7.5" do
      assert to_string(Application.spec(:req, :vsn)) == "0.7.5"
    end

    test "mix.exs pins the 0.7.5 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:req, "~> 0.7.5"})
    end

    test "companion lock is 0.7.5 and finch is 0.24.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"req": {:hex, :req, "0.7.5"|
      refute lock =~ ~s|"req": {:hex, :req, "0.7.4"|
      assert lock =~ ~s|"finch": {:hex, :finch, "0.24.0"|
    end

    test "get, post, head, request, and Test modules we use still load" do
      {:module, Req} = Code.ensure_loaded(Req)
      {:module, Req.Response} = Code.ensure_loaded(Req.Response)
      {:module, Req.Test} = Code.ensure_loaded(Req.Test)
      assert function_exported?(Req, :get, 1)
      assert function_exported?(Req, :get, 2)
      assert function_exported?(Req, :post, 2)
      assert function_exported?(Req, :put, 2)
      assert function_exported?(Req, :head, 2)
      assert function_exported?(Req, :request, 1)
      assert function_exported?(Req.Test, :stub, 2)
      assert function_exported?(Req.Test, :json, 2)
    end

    test "SSO still exchanges tokens with Req.post json, not params or aws_sigv4" do
      sso = File.read!(@sso_src)
      assert sso =~ "Req.post(conf.token_url, json: body)"
      refute sso =~ "path_params:"
      refute sso =~ "form_multipart:"
      refute sso =~ "aws_sigv4"
      refute sso =~ ~r/Req\.(get|post|request)\([^)]*\bparams:/
    end
  end

  describe "0.7.5 changelog" do
    test "documents SigV4 retry signing and 303 See Other GET" do
      changelog = File.read!(@changelog)

      v075 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "v0.7.5"))

      assert v075
      assert v075 =~ "Fix SigV4 signing on retries"
      assert v075 =~ "Change method to GET (except HEAD) on HTTP 303"
      refute v075 =~ "Breaking"
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

  describe "0.7.5 HTTP 303 See Other" do
    test "PUT follows Location with GET" do
      Req.Test.stub(SeeOtherStub, fn conn ->
        case {conn.method, conn.request_path} do
          {"PUT", "/resource"} ->
            conn
            |> Plug.Conn.put_resp_header("location", "/resource/result")
            |> Plug.Conn.send_resp(303, "")

          {"GET", "/resource/result"} ->
            Plug.Conn.send_resp(conn, 200, "see-other-get")

          other ->
            Plug.Conn.send_resp(conn, 500, inspect(other))
        end
      end)

      assert {:ok, %{status: 200, body: "see-other-get"}} =
               Req.request(
                 method: :put,
                 url: "http://example.com/resource",
                 body: "payload",
                 redirect_log_level: false,
                 plug: {Req.Test, SeeOtherStub}
               )
    end

    test "HEAD stays HEAD" do
      Req.Test.stub(SeeOtherStub, fn conn ->
        case {conn.method, conn.request_path} do
          {"HEAD", "/resource"} ->
            conn
            |> Plug.Conn.put_resp_header("location", "/resource/result")
            |> Plug.Conn.send_resp(303, "")

          {"HEAD", "/resource/result"} ->
            Plug.Conn.send_resp(conn, 200, "")

          other ->
            Plug.Conn.send_resp(conn, 500, inspect(other))
        end
      end)

      assert {:ok, %{status: 200}} =
               Req.head("http://example.com/resource",
                 redirect_log_level: false,
                 plug: {Req.Test, SeeOtherStub}
               )
    end

    test "POST on 301 still becomes GET" do
      Req.Test.stub(SeeOtherStub, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/from"} ->
            conn
            |> Plug.Conn.put_resp_header("location", "/to")
            |> Plug.Conn.send_resp(301, "")

          {"GET", "/to"} ->
            Plug.Conn.send_resp(conn, 200, "moved-get")

          other ->
            Plug.Conn.send_resp(conn, 500, inspect(other))
        end
      end)

      assert {:ok, %{status: 200, body: "moved-get"}} =
               Req.post("http://example.com/from",
                 body: "payload",
                 redirect_log_level: false,
                 plug: {Req.Test, SeeOtherStub}
               )
    end

    test "POST on 307 keeps POST" do
      Req.Test.stub(SeeOtherStub, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/from"} ->
            conn
            |> Plug.Conn.put_resp_header("location", "/to")
            |> Plug.Conn.send_resp(307, "")

          {"POST", "/to"} ->
            Plug.Conn.send_resp(conn, 200, "kept-post")

          other ->
            Plug.Conn.send_resp(conn, 500, inspect(other))
        end
      end)

      assert {:ok, %{status: 200, body: "kept-post"}} =
               Req.post("http://example.com/from",
                 body: "payload",
                 redirect_log_level: false,
                 plug: {Req.Test, SeeOtherStub}
               )
    end

    test "redirect step rewrites 303 except GET and HEAD" do
      source = File.read!(@steps_src)

      assert source =~
               "defp change_method(%{method: :post} = request, status) when status in [301, 302] do"

      assert source =~
               "defp change_method(%{method: method} = request, 303) when method not in [:get, :head] do"

      assert source =~ "defp change_to_get(request) do"
    end
  end

  describe "0.7.5 put_aws_sigv4 retries" do
    test "retry path deletes generated SigV4 headers before re-signing" do
      source = File.read!(@steps_src)
      assert source =~ ~s|"authorization"|
      assert source =~ ~s|"x-amz-content-sha256"|
      assert source =~ ~s|"x-amz-date"|
      assert source =~ ~s|"x-amz-security-token"|
      assert source =~ "Req.Request.delete_header(request, header)"
      assert source =~ "@aws_sigv4_generated_headers"
    end

    test "does not sign headers generated by a previous retry attempt" do
      test_pid = self()
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      try do
        Req.Test.stub(SigV4Stub, fn conn ->
          send(
            test_pid,
            {:authorization, Plug.Conn.get_req_header(conn, "authorization")}
          )

          n = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
          status = if n == 0, do: 500, else: 200
          Plug.Conn.send_resp(conn, status, "")
        end)

        assert {:ok, %{status: 200}} =
                 Req.put("http://example.com/",
                   aws_sigv4: [
                     access_key_id: "test-access-key",
                     secret_access_key: "test-secret-key",
                     service: :s3,
                     region: "us-west-2",
                     datetime: ~U[2026-09-03 18:20:32Z]
                   ],
                   body: "hello",
                   max_retries: 1,
                   retry: :transient,
                   retry_delay: 0,
                   retry_log_level: false,
                   plug: {Req.Test, SigV4Stub}
                 )

        assert_received {:authorization, [first_authorization]}
        assert_received {:authorization, [second_authorization]}
        assert first_authorization == second_authorization
        assert String.starts_with?(first_authorization, "AWS4-HMAC-SHA256")
      after
        Agent.stop(agent)
      end
    end
  end

  describe "0.7.4 put_params still holds" do
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

  describe "0.7.4 put_path_params on redirect still holds" do
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
                 redirect_log_level: false,
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
