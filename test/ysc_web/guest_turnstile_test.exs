defmodule YscWeb.GuestTurnstileTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mox

  alias YscWeb.GuestTurnstile

  setup :verify_on_exit!

  @token_params %{"cf-turnstile-response" => "token"}

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

  # Formats captured logs with the metadata GuestTurnstile attaches.
  @log_format [
    format: "$message $metadata",
    metadata: [:form, :turnstile_reason]
  ]

  describe "verify_token/3" do
    test "rejects a missing or blank token without calling Cloudflare" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        flunk("Turnstile.verify must not run without a token")
      end)

      assert {:error, :missing_token} =
               GuestTurnstile.verify_token(%{}, {127, 0, 0, 1})

      assert {:error, :missing_token} =
               GuestTurnstile.verify_token(
                 %{"cf-turnstile-response" => ""},
                 {127, 0, 0, 1}
               )

      assert {:error, :missing_token} =
               GuestTurnstile.verify_token(
                 %{"cf-turnstile-response" => ["token"]},
                 {127, 0, 0, 1}
               )
    end

    test "returns :ok when Cloudflare accepts the token" do
      stub(TurnstileMock, :verify, fn params, ip ->
        assert params == %{"cf-turnstile-response" => "token"}
        assert ip == {127, 0, 0, 1}
        {:ok, %{"success" => true}}
      end)

      assert :ok =
               GuestTurnstile.verify_token(
                 %{"cf-turnstile-response" => "token"},
                 {127, 0, 0, 1}
               )
    end

    test "returns the error when Cloudflare rejects the token" do
      reason = %{"error-codes" => ["invalid-input-response"]}
      stub(TurnstileMock, :verify, fn _params, _ip -> {:error, reason} end)

      assert {:error, ^reason} =
               GuestTurnstile.verify_token(
                 %{"cf-turnstile-response" => "bad"},
                 {127, 0, 0, 1}
               )
    end

    test "logs the form and Cloudflare's error codes on rejection" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:error, %{"error-codes" => ["invalid-input-response", "bad-request"]}}
      end)

      log =
        capture_log(@log_format, fn ->
          GuestTurnstile.verify_token(
            %{"cf-turnstile-response" => "bad"},
            {127, 0, 0, 1},
            form: "Contact"
          )
        end)

      assert log =~ "Turnstile check failed"
      assert log =~ "form=Contact"
      assert log =~ "turnstile_reason=invalid-input-response,bad-request"
    end

    test "logs a missing token" do
      log =
        capture_log(@log_format, fn ->
          GuestTurnstile.verify_token(%{}, {127, 0, 0, 1}, form: "Newsletter")
        end)

      assert log =~ "form=Newsletter"
      assert log =~ "turnstile_reason=missing_token"
    end

    test "does not log a successful check" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:ok, %{"success" => true}}
      end)

      log =
        capture_log(@log_format, fn ->
          GuestTurnstile.verify_token(
            %{"cf-turnstile-response" => "token"},
            {127, 0, 0, 1},
            form: "SuccessCheck"
          )
        end)

      refute log =~ "form=SuccessCheck"
    end
  end

  describe "rejection_reason/1" do
    test "summarizes reasons for the log line" do
      assert GuestTurnstile.rejection_reason(:missing_token) == "missing_token"

      assert GuestTurnstile.rejection_reason(%{
               "error-codes" => ["timeout-or-duplicate"]
             }) == "timeout-or-duplicate"

      assert GuestTurnstile.rejection_reason({:failed_connect, []}) ==
               "{:failed_connect, []}"
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
               GuestTurnstile.verify(socket(%{}), @token_params,
                 title: "Volunteer"
               )

      assert_received :turnstile_refreshed
      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "real person"

      assert Phoenix.Flash.get(socket.assigns.flash, "error_toast_title") ==
               "Volunteer"
    end

    test "logs the rejection under the toast title" do
      stub(TurnstileMock, :refresh, fn socket -> socket end)

      log =
        capture_log(@log_format, fn ->
          GuestTurnstile.verify(socket(%{}), %{}, title: "Volunteer")
        end)

      assert log =~ "form=Volunteer"
      assert log =~ "turnstile_reason=missing_token"
    end

    test "required: true verifies even when logged_in? is true" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:ok, %{"success" => true}}
      end)

      assert :ok =
               GuestTurnstile.verify(socket(%{logged_in?: true}), @token_params,
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
               GuestTurnstile.verify(socket(%{logged_in?: true}), @token_params,
                 title: "Registration",
                 required: true
               )

      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "real person"
    end

    test "rejects a missing token without calling Cloudflare" do
      test_pid = self()

      stub(TurnstileMock, :verify, fn _params, _ip ->
        flunk("Turnstile.verify must not run without a token")
      end)

      stub(TurnstileMock, :refresh, fn socket ->
        send(test_pid, :turnstile_refreshed)
        socket
      end)

      assert {:error, socket} =
               GuestTurnstile.verify(socket(%{}), %{}, title: "Contact")

      assert_received :turnstile_refreshed
      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "real person"
    end

    test "required: true rejects a missing token for signed-in sockets" do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        flunk("Turnstile.verify must not run without a token")
      end)

      stub(TurnstileMock, :refresh, fn socket -> socket end)

      assert {:error, _socket} =
               GuestTurnstile.verify(socket(%{logged_in?: true}), %{},
                 title: "Registration",
                 required: true
               )
    end
  end
end
