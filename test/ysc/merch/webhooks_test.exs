defmodule Ysc.Merch.WebhooksTest do
  use ExUnit.Case, async: false

  import Mox

  alias Ysc.Merch.{PrintfulEvents, Webhooks}
  alias Ysc.Printful.{ClientMock, Error}

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:ysc, :printful)
    on_exit(fn -> Application.put_env(:ysc, :printful, original) end)
    :ok
  end

  defp set_secret(secret) do
    Application.put_env(:ysc, :printful,
      api_token: "t",
      store_id: "1",
      webhook_secret: secret
    )
  end

  test "the callback URL carries the secret" do
    set_secret("s3cret")
    assert {:ok, url} = Webhooks.callback_url()
    assert url == "#{YscWeb.Endpoint.url()}/webhooks/printful/s3cret"
  end

  test "there is no callback URL without a secret" do
    for secret <- [nil, ""] do
      set_secret(secret)
      assert {:error, :no_secret} = Webhooks.callback_url()
      assert {:error, :no_secret} = Webhooks.register()
    end
  end

  test "registering subscribes our event types and returns a masked URL" do
    set_secret("s3cret")

    expect(ClientMock, :set_webhooks, fn url, types ->
      assert url =~ "/webhooks/printful/s3cret"
      assert types == PrintfulEvents.subscribed_types()
      {:ok, %{"url" => url}}
    end)

    assert {:ok, masked} = Webhooks.register()
    assert masked =~ "/webhooks/printful/"
    refute masked =~ "s3cret"
  end

  test "Printful errors are passed back" do
    set_secret("s3cret")
    error = %Error{type: :invalid, status: 400, message: "URL must be https"}
    expect(ClientMock, :set_webhooks, fn _, _ -> {:error, error} end)
    assert {:error, ^error} = Webhooks.register()
  end

  test "we subscribe to the events the handler understands" do
    types = PrintfulEvents.subscribed_types()

    for type <-
          ~w(package_shipped package_returned order_failed order_canceled order_put_hold order_updated),
        do: assert(type in types)
  end
end
