defmodule Ysc.Printful.ClientNotConfiguredTest do
  # Mutates global app env, so it cannot run alongside other Printful tests.
  use ExUnit.Case, async: false

  alias Ysc.Printful.{Client, Error}

  test "returns :not_configured without touching the network" do
    original = Application.get_env(:ysc, :printful)
    on_exit(fn -> Application.put_env(:ysc, :printful, original) end)
    Application.put_env(:ysc, :printful, api_token: nil)

    assert {:error, %Error{type: :not_configured}} = Client.list_sync_products()
  end
end
