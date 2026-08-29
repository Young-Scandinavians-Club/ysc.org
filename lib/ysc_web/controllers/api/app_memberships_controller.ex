defmodule YscWeb.Api.AppMembershipsController do
  @moduledoc """
  Membership plans and in-person membership sign-up for the admin/volunteer
  mobile app.

  Memberships are Stripe subscriptions, not one-off charges. The in-person
  flow is: the app first calls `create_setup_intent/2` below, whose Stripe
  Terminal SDK collects the member's card and — because that SetupIntent is
  created with the member's `customer` set — Stripe attaches the resulting
  `PaymentMethod` to the customer automatically as part of confirming it.
  `subscribe/2` then only needs to create the subscription with that already-
  attached payment method as the default — reusing
  `Ysc.Customers.create_subscription/2`, the same function used elsewhere, so
  subscription fulfillment/sync is unchanged. It must NOT attach the payment
  method again: Stripe's attach call errors if the method is already attached
  to a customer, which is exactly what happens here every time and was
  breaking every in-person membership sign-up with a generic payment error.
  """
  use YscWeb, :controller

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Customers
  alias Ysc.Subscriptions

  action_fallback YscWeb.Api.FallbackController

  @doc """
  Lists the available membership plans (mirrors `config :ysc, :membership_plans`,
  the same config the web membership settings page reads from).

  Lifetime is a board-awarded status with no Stripe price, so it is not
  offered as an in-person purchase — matching the website membership page.
  """
  def plans(conn, _params) do
    render(conn, :plans, plans: purchasable_membership_plans())
  end

  @doc """
  Looks up a member's current membership so the app can show its details
  (and block a duplicate sign-up) instead of offering the plan list, reusing
  the same `MembershipCache`/`UserAuth` helpers the website's account pages
  use to display membership status.
  """
  def status(conn, %{"member_id" => member_id}) do
    with {:ok, member} <- fetch_member(member_id) do
      membership = MembershipCache.get_active_membership(member)
      render(conn, :status, membership: membership)
    end
  end

  def status(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "member_id is required"})
  end

  def subscribe(conn, %{
        "member_id" => member_id,
        "plan" => plan_id,
        "payment_method_id" => payment_method_id
      }) do
    with {:ok, member} <- fetch_member(member_id),
         :ok <- reject_duplicate_membership(member),
         {:ok, plan} <- fetch_plan(plan_id),
         {:ok, subscription} <-
           Customers.create_subscription(member,
             prices: [%{price: plan.stripe_price_id, quantity: 1}],
             default_payment_method: payment_method_id,
             idempotency_key:
               "app_membership_#{member.id}_#{plan.stripe_price_id}"
           ) do
      render(conn, :subscription, subscription: subscription)
    end
  end

  def subscribe(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "member_id, plan, and payment_method_id are required"})
  end

  @doc """
  Records a membership the member paid for in person with cash or a check —
  no card is collected. Reuses `Subscriptions.create_subscription_paid_out_of_band/3`,
  the same primitive behind the web admin "Create membership (paid elsewhere)"
  action: it creates the Stripe subscription, marks the first invoice paid out
  of band, writes the local subscription + ledger payment, and sends the
  member the "paid elsewhere" confirmation email. The subscription has no card
  on file, so it simply lapses at period end rather than auto-renewing.

  The acting volunteer/admin (`conn.assigns.current_user`) is recorded as
  `recorded_by_id` for the audit log and Stripe metadata; it is never read
  from the request body.
  """
  def subscribe_offline(
        conn,
        %{"member_id" => member_id, "plan" => plan_id} = params
      ) do
    with {:ok, member} <- fetch_member(member_id),
         :ok <- reject_duplicate_membership(member),
         {:ok, plan} <- fetch_plan(plan_id),
         {:ok, payment_method} <- parse_offline_payment_method(params),
         {:ok, subscription} <-
           Subscriptions.create_subscription_paid_out_of_band(member, plan.id,
             recorded_by_id: conn.assigns.current_user.id,
             payment_method: payment_method,
             note: blank_to_nil(params["note"])
           ) do
      render(conn, :offline_subscription,
        subscription: subscription,
        plan: plan
      )
    end
  end

  def subscribe_offline(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "member_id and plan are required"})
  end

  @doc """
  Creates a Stripe Terminal SetupIntent for a member so the app can collect
  a card via tap-to-pay and save it (rather than charge it) — the resulting
  `payment_method_id` is then passed to `subscribe/2` above to create the
  actual subscription. Separate from `subscribe/2` because collecting the
  card is a client-side Terminal SDK step that happens in between.
  """
  def create_setup_intent(conn, %{"member_id" => member_id}) do
    with {:ok, member} <- fetch_member(member_id),
         :ok <- reject_duplicate_membership(member) do
      member = Customers.ensure_stripe_customer(member)

      case member.stripe_id do
        customer_id when is_binary(customer_id) and customer_id != "" ->
          case stripe_client().create_setup_intent(%{
                 customer: customer_id,
                 payment_method_types: ["card_present"]
               }) do
            {:ok, setup_intent} ->
              render(conn, :setup_intent, setup_intent: setup_intent)

            {:error, reason} ->
              {:error, reason}
          end

        _ ->
          {:error, "could not create a Stripe customer for this member"}
      end
    end
  end

  def create_setup_intent(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "member_id is required"})
  end

  defp fetch_member(id) do
    with {:ok, cast_id} <- Ecto.ULID.cast(id),
         %Accounts.User{} = member <- Accounts.get_user(cast_id) do
      {:ok, member}
    else
      _ -> {:error, :member_not_found}
    end
  end

  # `Customers.create_subscription/2` only inspects Stripe subscription
  # rows. Lifetime members and family sub-accounts who already inherit
  # membership have no such row, so without this check the door flow
  # would bill them for a new annual plan.
  defp reject_duplicate_membership(member) do
    if Accounts.has_active_membership?(member) do
      {:error, :user_already_has_active_subscription}
    else
      :ok
    end
  end

  defp purchasable_membership_plans do
    :ysc
    |> Application.get_env(:membership_plans, [])
    |> Enum.filter(&purchasable_plan?/1)
  end

  defp purchasable_plan?(%{stripe_price_id: price_id})
       when is_binary(price_id) and price_id != "",
       do: true

  defp purchasable_plan?(_), do: false

  defp fetch_plan(plan_id) when is_binary(plan_id) do
    case Enum.find(
           purchasable_membership_plans(),
           &(Atom.to_string(&1.id) == plan_id)
         ) do
      nil -> {:error, :invalid_plan}
      plan -> {:ok, plan}
    end
  end

  defp fetch_plan(_), do: {:error, :invalid_plan}

  # Defaults to cash — the overwhelmingly common in-person case — when the
  # client omits the field.
  defp parse_offline_payment_method(params) do
    case Map.get(params, "payment_method", "cash") do
      "cash" -> {:ok, :cash}
      "check" -> {:ok, :check}
      "other" -> {:ok, :other}
      _ -> {:error, :invalid_offline_payment_method}
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end
end
