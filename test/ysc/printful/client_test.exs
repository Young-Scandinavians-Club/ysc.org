defmodule Ysc.Printful.ClientTest do
  use ExUnit.Case, async: true

  alias Ysc.Printful.{Client, Error}

  setup {Req.Test, :set_req_test_from_context}

  defp stub(fun), do: Req.Test.stub(Client, fun)

  describe "list_sync_products/0" do
    test "walks every page and sends auth headers" do
      test_pid = self()

      stub(fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        send(test_pid, {:request, conn})
        offset = String.to_integer(conn.query_params["offset"])

        page =
          if offset == 0,
            do: Enum.map(1..100, &%{"id" => &1}),
            else: [%{"id" => 101}]

        Req.Test.json(conn, %{
          "code" => 200,
          "result" => page,
          "paging" => %{"total" => 101, "offset" => offset, "limit" => 100}
        })
      end)

      assert {:ok, products} = Client.list_sync_products()
      assert length(products) == 101

      assert_received {:request, conn}

      assert ["Bearer test-printful-token"] =
               Plug.Conn.get_req_header(conn, "authorization")

      assert ["123"] = Plug.Conn.get_req_header(conn, "x-pf-store-id")
    end
  end

  describe "get_catalog_product/1" do
    test "fetches the catalog product with its variants' colors" do
      test_pid = self()

      stub(fn conn ->
        send(test_pid, {:path, conn.request_path})

        Req.Test.json(conn, %{
          "code" => 200,
          "result" => %{
            "product" => %{"id" => 586},
            "variants" => [%{"id" => 15_114, "color_code" => "#1b1b1c"}]
          }
        })
      end)

      assert {:ok, %{"variants" => [%{"color_code" => "#1b1b1c"}]}} =
               Client.get_catalog_product(586)

      assert_received {:path, "/products/586"}
    end

    test "a catalog product Printful does not know is :not_found" do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"code" => 404, "result" => "Not Found"})
      end)

      assert {:error, %Error{type: :not_found}} = Client.get_catalog_product(1)
    end
  end

  describe "error mapping" do
    test "400 with an error body is a permanent :invalid error" do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{
          "code" => 400,
          "result" => "Bad address",
          "error" => %{
            "reason" => "BadRequest",
            "message" => "Recipient address is invalid"
          }
        })
      end)

      assert {:error, %Error{type: :invalid, status: 400} = error} =
               Client.create_order(%{"external_id" => "MRC-1"}, true)

      assert error.message == "Recipient address is invalid"
      refute Error.transient?(error)
    end

    test "429 is transient and exposes retry-after" do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "30")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"code" => 429, "result" => "Too many requests"})
      end)

      assert {:error, %Error{type: :rate_limited, retry_after: 30} = error} =
               Client.get_order(1)

      assert Error.transient?(error)
    end

    test "5xx is transient" do
      stub(fn conn ->
        conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
      end)

      assert {:error, %Error{type: :server} = error} = Client.get_order(1)
      assert Error.transient?(error)
    end

    test "404 is :not_found" do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"code" => 404, "result" => "Not found"})
      end)

      assert {:error, %Error{type: :not_found}} =
               Client.get_order_by_external_id("MRC-1")
    end

    test "transport failures are transient :network errors" do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      assert {:error, %Error{type: :network} = error} = Client.get_order(1)
      assert Error.transient?(error)
    end
  end

  describe "create_order/2" do
    test "confirm flag is sent as a query param" do
      test_pid = self()

      stub(fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        send(test_pid, {:query, conn.query_params})

        Req.Test.json(conn, %{
          "code" => 200,
          "result" => %{"id" => 9, "status" => "pending"}
        })
      end)

      assert {:ok, %{"id" => 9}} = Client.create_order(%{}, true)
      assert_received {:query, %{"confirm" => "true"}}

      assert {:ok, _} = Client.create_order(%{}, false)
      assert_received {:query, query}
      refute Map.has_key?(query, "confirm")
    end
  end
end
