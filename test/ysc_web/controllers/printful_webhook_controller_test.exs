defmodule YscWeb.PrintfulWebhookControllerTest do
  use YscWeb.ConnCase, async: false

  import Swoosh.TestAssertions
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Orders, Shipment}
  alias Ysc.Repo

  @secret "test-printful-webhook-secret"

  setup do
    original = Application.get_env(:ysc, Ysc.PrintfulWebhookRateLimit)
    Application.put_env(:ysc, Ysc.PrintfulWebhookRateLimit, ip_limit: 1_000)

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.PrintfulWebhookRateLimit, original)
    end)

    member = member_fixture()
    %{order: purchase_order_fixture(member, :submitted)}
  end

  defp post_event(conn, token, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/webhooks/printful/#{token}", payload)
  end

  test "a valid event is accepted and applied", %{conn: conn, order: order} do
    payload =
      printful_event("package_shipped", order, %{
        "shipment" => printful_shipment()
      })

    assert conn |> post_event(@secret, payload) |> response(200) == "ok"

    assert Orders.get_order!(order.id).status == :shipped
    assert Repo.aggregate(Shipment, :count) == 1
    assert_email_sent(subject: ~r/on its way/)
  end

  test "a wrong token is rejected and nothing happens", %{
    conn: conn,
    order: order
  } do
    payload =
      printful_event("package_shipped", order, %{
        "shipment" => printful_shipment()
      })

    assert conn |> post_event("wrong", payload) |> response(401)
    assert Orders.get_order!(order.id).status == :submitted
    assert Repo.aggregate(Shipment, :count) == 0
  end

  test "without a configured secret every request is rejected", %{
    conn: conn,
    order: order
  } do
    original = Application.get_env(:ysc, :printful)
    on_exit(fn -> Application.put_env(:ysc, :printful, original) end)

    for secret <- [nil, ""] do
      Application.put_env(:ysc, :printful,
        api_token: "t",
        webhook_secret: secret
      )

      payload = printful_event("order_failed", order)

      assert conn |> post_event("anything", payload) |> response(401)
      assert conn |> post_event(@secret, payload) |> response(401)
    end

    assert Orders.get_order!(order.id).status == :submitted
  end

  test "malformed payloads are a 400, not a crash", %{conn: conn} do
    for payload <- [
          %{},
          %{"type" => "order_failed"},
          %{"type" => 5, "data" => %{}},
          %{"type" => "x", "data" => "nope"}
        ] do
      assert conn |> post_event(@secret, payload) |> response(400)
    end
  end

  test "events for unknown orders are acknowledged", %{conn: conn} do
    payload = %{
      "type" => "order_failed",
      "data" => %{"order" => %{"id" => 1, "external_id" => "MRC-NOPE"}}
    }

    assert conn |> post_event(@secret, payload) |> response(200)
  end

  test "the secret is not accepted as a query param or header", %{
    conn: conn,
    order: order
  } do
    payload = printful_event("order_failed", order)

    assert conn
           |> put_req_header("content-type", "application/json")
           |> put_req_header("x-token", @secret)
           |> post("/webhooks/printful/nope?token=#{@secret}", payload)
           |> response(401)
  end

  test "only POST is accepted", %{conn: conn} do
    assert conn |> get(~p"/webhooks/printful/#{@secret}") |> response(404)
  end

  test "repeated deliveries of one event do not repeat its effects", %{
    conn: conn,
    order: order
  } do
    payload =
      printful_event("package_shipped", order, %{
        "shipment" => printful_shipment()
      })

    for _ <- 1..3,
        do: assert(conn |> post_event(@secret, payload) |> response(200))

    assert Repo.aggregate(Shipment, :count) == 1
    assert_email_sent(subject: ~r/on its way/)
    refute_email_sent()
  end
end
