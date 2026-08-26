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
end
