defmodule Ysc.Stripe.DonationPaymentLinkValidateTest do
  @moduledoc """
  Boot-time guard for misconfigured `:stripe_donation_payment_links`.

  `Application` calls `validate_configured_links!/0` on startup; a missing
  QuickBooks income account must raise so we never book donations to a void.
  """
  use ExUnit.Case, async: false

  alias Ysc.Stripe.DonationPaymentLink

  setup do
    previous = Application.get_env(:ysc, :stripe_donation_payment_links)

    on_exit(fn ->
      if previous do
        Application.put_env(:ysc, :stripe_donation_payment_links, previous)
      else
        Application.delete_env(:ysc, :stripe_donation_payment_links)
      end
    end)

    :ok
  end

  test "returns :ok when every configured URL has an income account" do
    Application.put_env(:ysc, :stripe_donation_payment_links,
      links: [
        %{
          url: "https://donate.stripe.com/test_link_ok",
          account: "Kitchen Fund"
        }
      ]
    )

    assert :ok = DonationPaymentLink.validate_configured_links!()
  end

  test "returns :ok for the known Tahoe kitchen URL without an explicit account" do
    Application.put_env(:ysc, :stripe_donation_payment_links,
      links: [%{url: "https://donate.stripe.com/28E5kEaLcg63aPW6nr2Ji03"}]
    )

    assert :ok = DonationPaymentLink.validate_configured_links!()
  end

  test "returns :ok when config is empty or absent" do
    Application.delete_env(:ysc, :stripe_donation_payment_links)
    assert :ok = DonationPaymentLink.validate_configured_links!()

    Application.put_env(:ysc, :stripe_donation_payment_links, links: [])
    assert :ok = DonationPaymentLink.validate_configured_links!()
  end

  test "raises when a configured URL has no QuickBooks income account" do
    url = "https://donate.stripe.com/test_link_missing_account"

    Application.put_env(:ysc, :stripe_donation_payment_links,
      links: [%{url: url}]
    )

    assert_raise RuntimeError,
                 ~r/Donation payment links need a QuickBooks income account/,
                 fn ->
                   DonationPaymentLink.validate_configured_links!()
                 end
  end

  test "ignores a configured class segment and still requires an account" do
    url = "https://donate.stripe.com/test_link_class_only"

    Application.put_env(:ysc, :stripe_donation_payment_links,
      links: [%{url: url, class: "Administration"}]
    )

    assert_raise RuntimeError,
                 ~r/Donation payment links need a QuickBooks income account/,
                 fn ->
                   DonationPaymentLink.validate_configured_links!()
                 end
  end

  test "accepts string-key maps and ignores blank URLs" do
    Application.put_env(:ysc, :stripe_donation_payment_links,
      links: [
        %{"url" => "", "account" => "Ignored"},
        %{
          "url" => "https://donate.stripe.com/test_string_keys",
          "account" => "Roof Fund"
        }
      ]
    )

    assert :ok = DonationPaymentLink.validate_configured_links!()
  end
end
