defmodule Ysc.Keila.ClientTest do
  use Ysc.DataCase, async: false

  alias Ysc.Keila.Client

  setup do
    # Save original config
    original_keila_config = Application.get_env(:ysc, :keila)

    on_exit(fn ->
      # Restore config
      if original_keila_config do
        Application.put_env(:ysc, :keila, original_keila_config)
      else
        Application.delete_env(:ysc, :keila)
      end
    end)

    :ok
  end

  describe "subscribe_email/2" do
    test "returns :not_configured when Keila is not configured" do
      # Clear all config
      Application.delete_env(:ysc, :keila)

      assert {:error, :not_configured} =
               Client.subscribe_email("test@example.com", [])
    end

    test "returns :not_configured when form_id is missing" do
      # Set API config but not form_id
      Application.put_env(:ysc, :keila,
        api_url: "http://localhost:4000",
        api_key: "test_token"
      )

      assert {:error, :not_configured} =
               Client.subscribe_email("test@example.com", [])
    end

    test "attempts HTTP request with valid configuration" do
      # Set minimal config
      Application.put_env(:ysc, :keila,
        api_url: "http://localhost:4000",
        api_key: "test_token",
        form_id: "test_form"
      )

      # This will attempt the HTTP request and likely fail with network_error
      # since there's no real Keila instance, but that's expected
      result = Client.subscribe_email("test@example.com", [])

      # Should not return configuration errors
      refute result == {:error, :not_configured}
    end

    test "accepts additional options like first_name, last_name, and data" do
      Application.put_env(:ysc, :keila,
        api_url: "http://localhost:4000",
        api_key: "test_token",
        form_id: "test_form"
      )

      metadata = %{"user_id" => "123", "role" => "member"}

      result =
        Client.subscribe_email("test@example.com",
          first_name: "John",
          last_name: "Doe",
          data: metadata
        )

      # Should not return configuration errors
      refute result == {:error, :not_configured}
    end
  end

  describe "unsubscribe_email/2" do
    test "returns :not_configured when Keila is not configured" do
      # Clear all config
      Application.delete_env(:ysc, :keila)

      assert {:error, :not_configured} =
               Client.unsubscribe_email("test@example.com", [])
    end

    test "attempts HTTP request with valid configuration" do
      Application.put_env(:ysc, :keila,
        api_url: "http://localhost:4000",
        api_key: "test_token"
      )

      # This will attempt the HTTP request
      result = Client.unsubscribe_email("test@example.com", [])

      # Should not return configuration errors
      refute result == {:error, :not_configured}
    end
  end
end
