defmodule YscWeb.Workers.KeilaSubscriberTest do
  use Ysc.DataCase, async: true
  import Mox

  alias YscWeb.Workers.KeilaSubscriber

  setup :verify_on_exit!

  setup do
    Application.put_env(:ysc, :keila_client, Ysc.KeilaMock)

    on_exit(fn ->
      Application.put_env(:ysc, :keila_client, Ysc.Keila.ClientStub)
    end)

    :ok
  end

  describe "perform/1 - subscribe" do
    test "subscribes successfully" do
      email = "test@example.com"
      expect(Ysc.KeilaMock, :subscribe_email, fn ^email, _opts -> :ok end)

      assert :ok =
               KeilaSubscriber.perform(%Oban.Job{
                 args: %{"email" => email, "action" => "subscribe"}
               })
    end

    test "subscribes with first_name, last_name, and metadata" do
      email = "test@example.com"
      first_name = "John"
      last_name = "Doe"
      metadata = %{"user_id" => "123", "role" => "member"}

      expect(Ysc.KeilaMock, :subscribe_email, fn ^email, opts ->
        assert opts[:first_name] == first_name
        assert opts[:last_name] == last_name
        assert opts[:data] == metadata
        :ok
      end)

      assert :ok =
               KeilaSubscriber.perform(%Oban.Job{
                 args: %{
                   "email" => email,
                   "action" => "subscribe",
                   "first_name" => first_name,
                   "last_name" => last_name,
                   "data" => metadata
                 }
               })
    end

    test "handles invalid email error" do
      email = "invalid"

      # No expectation needed because Ysc.Keila.subscribe_email/2 returns early for invalid emails

      assert {:error, "Invalid email address"} =
               KeilaSubscriber.perform(%Oban.Job{
                 args: %{"email" => email, "action" => "subscribe"}
               })
    end

    test "handles not configured error as ok" do
      email = "test@example.com"

      expect(Ysc.KeilaMock, :subscribe_email, fn ^email, _opts ->
        {:error, :not_configured}
      end)

      assert :ok =
               KeilaSubscriber.perform(%Oban.Job{
                 args: %{"email" => email, "action" => "subscribe"}
               })
    end
  end

  describe "perform/1 - unsubscribe" do
    test "unsubscribes successfully" do
      email = "test@example.com"
      expect(Ysc.KeilaMock, :unsubscribe_email, fn ^email, _opts -> :ok end)

      assert :ok =
               KeilaSubscriber.perform(%Oban.Job{
                 args: %{"email" => email, "action" => "unsubscribe"}
               })
    end
  end

  describe "perform/1 - default action" do
    test "subscribes when no action provided" do
      email = "test@example.com"
      expect(Ysc.KeilaMock, :subscribe_email, fn ^email, _opts -> :ok end)

      assert :ok = KeilaSubscriber.perform(%Oban.Job{args: %{"email" => email}})
    end
  end
end
