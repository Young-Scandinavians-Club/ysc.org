defmodule Ysc.KeilaTest do
  use Ysc.DataCase, async: true
  import Mox

  alias Ysc.Keila

  setup :verify_on_exit!

  setup do
    Application.put_env(:ysc, :keila_client, Ysc.KeilaMock)

    on_exit(fn ->
      Application.put_env(:ysc, :keila_client, Ysc.Keila.ClientStub)
    end)

    :ok
  end

  describe "subscribe_email/2" do
    test "returns :ok when subscription is successful" do
      expect(Ysc.KeilaMock, :subscribe_email, fn "test@example.com", _opts ->
        :ok
      end)

      assert :ok = Keila.subscribe_email("test@example.com")
    end

    test "returns error for invalid email" do
      assert {:error, :invalid_email} = Keila.subscribe_email("invalid")
      assert {:error, :invalid_email} = Keila.subscribe_email("")
    end

    test "forwards options to client" do
      expect(Ysc.KeilaMock, :subscribe_email, fn "test@example.com",
                                                 [
                                                   project_id: "p1",
                                                   form_id: "f1"
                                                 ] ->
        :ok
      end)

      assert :ok =
               Keila.subscribe_email("test@example.com",
                 project_id: "p1",
                 form_id: "f1"
               )
    end
  end

  describe "unsubscribe_email/2" do
    test "returns :ok when unsubscription is successful" do
      expect(Ysc.KeilaMock, :unsubscribe_email, fn "test@example.com", _opts ->
        :ok
      end)

      assert :ok = Keila.unsubscribe_email("test@example.com")
    end
  end

  describe "get_subscription_status/2" do
    test "returns status when found" do
      expect(Ysc.KeilaMock, :get_subscription_status, fn "test@example.com",
                                                         _opts ->
        {:ok, :active}
      end)

      assert {:ok, :active} = Keila.get_subscription_status("test@example.com")
    end

    test "returns :not_found when contact doesn't exist" do
      expect(Ysc.KeilaMock, :get_subscription_status, fn "test@example.com",
                                                         _opts ->
        {:ok, :not_found}
      end)

      assert {:ok, :not_found} =
               Keila.get_subscription_status("test@example.com")
    end
  end
end
