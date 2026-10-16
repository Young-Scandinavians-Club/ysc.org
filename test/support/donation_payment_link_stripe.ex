defmodule Ysc.Stripe.DonationPaymentLinkTestClient do
  @moduledoc false

  @tahoe_url "https://donate.stripe.com/28E5kEaLcg63aPW6nr2Ji03"

  def retrieve_payment_link(id, opts \\ %{}) do
    send(self(), {:retrieve_payment_link, id, opts})
    do_retrieve_payment_link(id)
  end

  defp do_retrieve_payment_link("plink_tahoe_kitchen") do
    {:ok,
     %{
       id: "plink_tahoe_kitchen",
       url: @tahoe_url,
       submit_type: "donate",
       line_items: %{
         data: [
           %{
             description: "Tahoe Kitchen Fund",
             price: %{
               product: %{
                 id: "prod_VRTmLog8ZOVsiv",
                 name: "Tahoe Kitchen Fund"
               }
             }
           }
         ]
       }
     }}
  end

  defp do_retrieve_payment_link("plink_sauna_roof") do
    {:ok,
     %{
       id: "plink_sauna_roof",
       url: "https://donate.stripe.com/new_unconfigured_sauna_link",
       submit_type: "donate",
       line_items: %{
         data: [
           %{
             description: "Sauna Roof Fund",
             price: %{
               product: %{
                 id: "prod_sauna_roof",
                 name: "Sauna Roof Fund"
               }
             }
           }
         ]
       }
     }}
  end

  defp do_retrieve_payment_link("plink_renamed_fund") do
    name = Process.get(:plink_renamed_fund_product_name, "Old Fund Name")

    {:ok,
     %{
       id: "plink_renamed_fund",
       url: "https://donate.stripe.com/renamed_fund_link",
       submit_type: "donate",
       line_items: %{
         data: [
           %{
             description: name,
             price: %{
               product: %{
                 id: "prod_renamed_fund",
                 name: name
               }
             }
           }
         ]
       }
     }}
  end

  defp do_retrieve_payment_link("plink_other") do
    {:ok, %{id: "plink_other", url: "https://buy.stripe.com/not-a-donation"}}
  end

  defp do_retrieve_payment_link("plink_missing") do
    {:error, :stripe_down}
  end

  defp do_retrieve_payment_link(id), do: {:error, {:not_found, id}}

  # No expanded charge, so the donation books an estimated fee instead of
  # calling retrieve_charge.
  def retrieve_payment_intent(id, _opts) when is_binary(id) do
    send(self(), {:retrieve_payment_intent, id})
    {:ok, %{id: id, amount: 5_000}}
  end
end
