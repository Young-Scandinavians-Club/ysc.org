defmodule Ysc.Stripe.HttpClientTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.HttpClient
  alias Ysc.Stripe.HttpClient.ReqStub

  @api_key "sk_test_stub"
  @stripe_url "https://api.stripe.com/v1/payment_intents"

  setup context do
    Req.Test.set_req_test_from_context(context)

    on_exit(fn ->
      Application.delete_env(:ysc, :stripe_http_req_opts)
    end)

    Application.put_env(:ysc, :stripe_http_req_opts,
      plug: {Req.Test, Ysc.Stripe.HttpClient.ReqStub}
    )

    :ok
  end

  test "request/5 returns hackney-compatible success tuple for Stripe-style headers" do
    Req.Test.stub(ReqStub, fn conn ->
      assert {"connection", "keep-alive"} in conn.req_headers
      assert {"accept-encoding", "gzip"} in conn.req_headers

      Req.Test.json(conn, %{"id" => "pi_test", "object" => "payment_intent"})
    end)

    headers = [
      {"Accept", "application/json; charset=utf8"},
      {"Accept-Encoding", "gzip"},
      {"Authorization", "Bearer #{@api_key}"},
      {"Connection", "keep-alive"},
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Stripe-Version", "2025-11-17.clover"},
      {"User-Agent", "Stripe/v1 stripe-elixir/test"}
    ]

    assert {:ok, 200, resp_headers, body} =
             HttpClient.request(
               :post,
               @stripe_url,
               headers,
               "amount=100&currency=usd",
               []
             )

    assert {"content-type", "application/json; charset=utf-8"} in resp_headers
    assert Jason.decode!(body)["id"] == "pi_test"
  end

  test "request/5 returns hackney-compatible error tuple" do
    Req.Test.stub(ReqStub, fn conn ->
      Plug.Conn.send_resp(conn, 503, "unavailable")
    end)

    headers = [
      {"Authorization", "Bearer #{@api_key}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    assert {:ok, 503, _headers, "unavailable"} =
             HttpClient.request(
               :post,
               @stripe_url,
               headers,
               "amount=100&currency=usd",
               []
             )
  end

  test "request/5 encodes multipart bodies with string field names" do
    Req.Test.stub(ReqStub, fn conn ->
      assert conn.method == "POST"

      assert {"content-type", "multipart/form-data; boundary=" <> _} =
               List.keyfind(conn.req_headers, "content-type", 0)

      assert conn.body_params == %{
               "file" => "binary-payload",
               "purpose" => "identity_document"
             }

      Req.Test.json(conn, %{"id" => "file_test", "object" => "file"})
    end)

    headers = [
      {"Authorization", "Bearer #{@api_key}"},
      {"Content-Type", "multipart/form-data"}
    ]

    multipart_body =
      {:multipart,
       [
         {"file", "binary-payload"},
         {"purpose", "identity_document"}
       ]}

    assert {:ok, 200, _headers, body} =
             HttpClient.request(
               :post,
               "https://api.stripe.com/v1/files",
               headers,
               multipart_body,
               []
             )

    assert Jason.decode!(body)["id"] == "file_test"
  end

  test "request/5 keeps GET method when body is empty string" do
    list_url = "https://api.stripe.com/v1/balance_transactions?limit=1"

    Req.Test.stub(ReqStub, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"object" => "list", "data" => []})
    end)

    headers = [
      {"Authorization", "Bearer #{@api_key}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    assert {:ok, 200, _headers, body} =
             HttpClient.request(:get, list_url, headers, "", [])

    assert Jason.decode!(body)["object"] == "list"
  end
end
