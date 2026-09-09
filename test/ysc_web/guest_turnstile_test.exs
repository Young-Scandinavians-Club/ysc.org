defmodule YscWeb.GuestTurnstileTest do
  use ExUnit.Case, async: true

  import Mox

  alias YscWeb.GuestTurnstile

  setup :verify_on_exit!

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            logged_in?: false,
            remote_ip: {127, 0, 0, 1}
          },
          assigns
        )
    }
  end

  describe "module/0" do
    test "resolves the configured Turnstile module" do
      assert GuestTurnstile.module() == TurnstileMock
    end
  end

  describe "error_message/0" do
    test "explains how to retry after a failed check" do
      assert GuestTurnstile.error_message() =~ "real person"
      assert GuestTurnstile.error_message() =~ "try submitting again"
    end
  end

  describe "verify/3" do
    test "skips Turnstile for signed-in members" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        flunk("Turnstile.verify must not run for signed-in members")
      end)

      assert :ok =
               GuestTurnstile.verify(socket(%{logged_in?: true}), %{},
                 title: "Contact"
               )
    end

    test "verifies guests and returns :ok on success" do
      stub(TurnstileMock, :verify, fn params, ip ->
        assert params == %{"cf-turnstile-response" => "token"}
        assert ip == {127, 0, 0, 1}
        {:ok, %{"success" => true}}
      end)

      assert :ok =
               GuestTurnstile.verify(
                 socket(%{}),
                 %{"cf-turnstile-response" => "token"},
                 title: "Contact"
               )
    end

    test "toasts, refreshes, and returns the socket on failure" do
      test_pid = self()

      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:error, %{"error-codes" => ["invalid-input-response"]}}
      end)

      stub(TurnstileMock, :refresh, fn socket ->
        send(test_pid, :turnstile_refreshed)
        socket
      end)

      assert {:error, socket} =
               GuestTurnstile.verify(socket(%{}), %{}, title: "Volunteer")

      assert_received :turnstile_refreshed
      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "real person"

      assert Phoenix.Flash.get(socket.assigns.flash, "error_toast_title") ==
               "Volunteer"
    end

    test "required: true verifies even when logged_in? is true" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:ok, %{"success" => true}}
      end)

      assert :ok =
               GuestTurnstile.verify(socket(%{logged_in?: true}), %{},
                 title: "Registration",
                 required: true
               )
    end

    test "required: true still rejects failed checks for signed-in sockets" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:error, %{"error-codes" => ["invalid-input-response"]}}
      end)

      stub(TurnstileMock, :refresh, fn socket -> socket end)

      assert {:error, socket} =
               GuestTurnstile.verify(socket(%{logged_in?: true}), %{},
                 title: "Registration",
                 required: true
               )

      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "real person"
    end
  end
end
