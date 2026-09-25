defmodule YscWeb.NewsletterSubscribeTest do
  use Ysc.DataCase, async: true

  alias Ysc.Newsletter
  alias YscWeb.NewsletterSubscribe

  describe "subscribed?/1" do
    test "returns false for nil and unknown emails" do
      refute NewsletterSubscribe.subscribed?(nil)
      refute NewsletterSubscribe.subscribed?("nobody@example.com")
    end

    test "returns true only when the subscriber is actively subscribed" do
      email = "nl_sub_#{System.unique_integer([:positive])}@example.com"

      assert {:ok, subscriber} =
               Newsletter.subscribe(email, source: "test")

      assert NewsletterSubscribe.subscribed?(email)
      assert NewsletterSubscribe.subscribed?(subscriber)

      assert {:ok, _} = Newsletter.unsubscribe(email)
      refute NewsletterSubscribe.subscribed?(email)
    end

    test "accepts a user-shaped map" do
      email = "nl_user_#{System.unique_integer([:positive])}@example.com"

      assert {:ok, _} = Newsletter.subscribe(email, source: "test")
      assert NewsletterSubscribe.subscribed?(%{email: email})
    end
  end

  describe "guest_error/1" do
    test "maps known failure atoms to member-facing copy" do
      assert NewsletterSubscribe.guest_error(:invalid_email) ==
               "Please enter a valid email address."

      assert NewsletterSubscribe.guest_error(:no_mx_records) =~
               "email domain appears to be invalid"

      assert NewsletterSubscribe.guest_error(:disposable_email) =~
               "Temporary email addresses"

      assert NewsletterSubscribe.guest_error(:rate_limited) =~
               "Too many subscription attempts"

      assert NewsletterSubscribe.guest_error(:turnstile) =~
               "complete the verification"
    end

    test "uses the email changeset message when present" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{}, [:email])
        |> Ecto.Changeset.add_error(:email, "has already been taken")

      assert NewsletterSubscribe.guest_error(changeset) ==
               "has already been taken"
    end

    test "falls back to a generic message for other changeset errors" do
      changeset =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.add_error(:name, "is invalid")

      assert NewsletterSubscribe.guest_error(changeset) =~ "info@ysc.org"
    end

    test "falls back to a generic message for unknown reasons" do
      assert NewsletterSubscribe.guest_error(:timeout) =~ "info@ysc.org"
      assert NewsletterSubscribe.guest_error("nope") =~ "info@ysc.org"
    end
  end

  describe "request_guest/2 Turnstile" do
    setup do
      # Unique IP per test so the shared Hammer IP bucket can't rate-limit us.
      ip = {10, 0, 0, rem(System.unique_integer([:positive]), 250) + 1}

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, remote_ip: ip}
      }

      email = "nl_turnstile_#{System.unique_integer([:positive])}@example.com"
      %{socket: socket, email: email, ip: ip}
    end

    test "rejects a missing token without calling Cloudflare", %{
      socket: socket,
      email: email
    } do
      test_pid = self()

      stub(TurnstileMock, :verify, fn _params, _ip ->
        flunk("Turnstile.verify must not run without a token")
      end)

      stub(TurnstileMock, :refresh, fn socket ->
        send(test_pid, :turnstile_refreshed)
        socket
      end)

      socket = NewsletterSubscribe.request_guest(socket, %{"email" => email})

      assert socket.assigns.newsletter_error ==
               NewsletterSubscribe.guest_error(:turnstile)

      assert_received :turnstile_refreshed
      assert is_nil(Newsletter.get_subscriber_by_email(email))
    end

    test "rejects a blank token", %{socket: socket, email: email} do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        flunk("Turnstile.verify must not run with a blank token")
      end)

      socket =
        NewsletterSubscribe.request_guest(socket, %{
          "email" => email,
          "cf-turnstile-response" => ""
        })

      assert socket.assigns.newsletter_error ==
               NewsletterSubscribe.guest_error(:turnstile)

      assert is_nil(Newsletter.get_subscriber_by_email(email))
    end

    test "rejects a failed Turnstile check", %{socket: socket, email: email} do
      test_pid = self()

      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:error, %{"error-codes" => ["invalid-input-response"]}}
      end)

      stub(TurnstileMock, :refresh, fn socket ->
        send(test_pid, :turnstile_refreshed)
        socket
      end)

      socket =
        NewsletterSubscribe.request_guest(socket, %{
          "email" => email,
          "cf-turnstile-response" => "bad-token"
        })

      assert socket.assigns.newsletter_error ==
               NewsletterSubscribe.guest_error(:turnstile)

      assert_received :turnstile_refreshed
      assert is_nil(Newsletter.get_subscriber_by_email(email))
    end

    test "subscribes after a successful Turnstile check", %{
      socket: socket,
      email: email,
      ip: ip
    } do
      params = %{"email" => email, "cf-turnstile-response" => "good-token"}

      expect(TurnstileMock, :verify, fn ^params, ^ip ->
        {:ok, %{"success" => true}}
      end)

      socket = NewsletterSubscribe.request_guest(socket, params)

      assert socket.assigns.newsletter_submitted
      assert is_nil(socket.assigns.newsletter_error)
      refute Newsletter.get_subscriber_by_email(email).subscribed
    end
  end
end
