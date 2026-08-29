defmodule Ysc.ReqUpgradeTest do
  @moduledoc """
  Guards the req 0.7.3 → 0.7.4 upgrade.

  0.7.4 is a patch: `put_params` overwrites existing query keys but keeps
  explicit duplicates, and redirects drop `:path_params` so the Location
  path is not rewritten. We do not pass `:params` or `:path_params` in app
  code; Stripe GET-with-body stays GET (0.7.3). No Elixir API breaks.
  """
  use ExUnit.Case, async: true

  alias Ysc.ReqUpgradeTest.ParamsStub
  alias Ysc.ReqUpgradeTest.RedirectStub

  setup context do
    Req.Test.set_req_test_from_context(context)
    :ok
  end

  describe "0.7.4 Hex lock and public APIs" do
    test "locks the Hex package to 0.7.4" do
      assert to_string(Application.spec(:req, :vsn)) == "0.7.4"
    end

    test "get, post, request, and Test modules we use still load" do
      assert function_exported?(Req, :get, 1)
      assert function_exported?(Req, :get, 2)
      assert function_exported?(Req, :post, 2)
      assert function_exported?(Req, :request, 1)
      assert {:module, Req.Response} = Code.ensure_loaded(Req.Response)
      assert {:module, Req.Test} = Code.ensure_loaded(Req.Test)
      assert function_exported?(Req.Test, :stub, 2)
      assert function_exported?(Req.Test, :json, 2)
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
