defmodule Ysc.Stripe.DonationPaymentLinkAccountTest do
  use Ysc.DataCase, async: false

  import Mox

  alias Ysc.Quickbooks.ClientMock
  alias Ysc.Stripe.WebhookHandler

  setup :verify_on_exit!

  setup do
    previous_stripe = Application.get_env(:ysc, :stripe_client)
    previous_qb = Application.get_env(:ysc, :quickbooks_client)

    Application.put_env(
      :ysc,
      :stripe_client,
      Ysc.Stripe.DonationPaymentLinkTestClient
    )

    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    on_exit(fn ->
      restore(:stripe_client, previous_stripe)
      restore(:quickbooks_client, previous_qb)
    end)

    :ok
  end

  test "payment_link.created creates the income account named after the product" do
    expect(ClientMock, :query_account_by_name, fn "Sauna Roof Fund" ->
      {:error, :not_found}
    end)

    expect(ClientMock, :create_account, fn "Sauna Roof Fund", opts ->
      assert opts[:account_type] == "Income"
      {:ok, "qb_sauna_roof"}
    end)

    assert :ok =
             WebhookHandler.handle_webhook_event("payment_link.created", %{
               "id" => "plink_sauna_roof",
               "object" => "payment_link"
             })

    assert_received {:retrieve_payment_link, "plink_sauna_roof",
                     %{expand: ["line_items.data.price.product"]}}
  end

  test "payment_link.updated reuses an account that already exists" do
    expect(ClientMock, :query_account_by_name, fn "Sauna Roof Fund" ->
      {:ok, "qb_sauna_roof"}
    end)

    assert :ok =
             WebhookHandler.handle_webhook_event("payment_link.updated", %{
               "id" => "plink_sauna_roof",
               "object" => "payment_link"
             })
  end

  test "a link that is not a donation link gets no QuickBooks account" do
    assert :ok =
             WebhookHandler.handle_webhook_event("payment_link.created", %{
               "id" => "plink_other",
               "object" => "payment_link"
             })

    assert_received {:retrieve_payment_link, "plink_other", _opts}
  end

  defp restore(key, nil), do: Application.delete_env(:ysc, key)
  defp restore(key, value), do: Application.put_env(:ysc, key, value)
end
