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

  action_fallback YscWeb.Api.FallbackController

  @doc """
  Lists the available membership plans (mirrors `config :ysc, :membership_plans`,
  the same config the web membership settings page reads from).
  """
  def plans(conn, _params) do
    plans = Application.get_env(:ysc, :membership_plans, [])
    render(conn, :plans, plans: plans)
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
  Creates a Stripe Terminal SetupIntent for a member so the app can collect
  a card via tap-to-pay and save it (rather than charge it) — the resulting
  `payment_method_id` is then passed to `subscribe/2` above to create the
  actual subscription. Separate from `subscribe/2` because collecting the
  card is a client-side Terminal SDK step that happens in between.
  """
  def create_setup_intent(conn, %{"member_id" => member_id}) do
    with {:ok, member} <- fetch_member(member_id) do
      member = Customers.ensure_stripe_customer(member)

      case stripe_client().create_setup_intent(%{
             customer: member.stripe_id,
             payment_method_types: ["card_present"]
           }) do
        {:ok, setup_intent} ->
          render(conn, :setup_intent, setup_intent: setup_intent)

        {:error, reason} ->
          {:error, reason}
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

  defp fetch_plan(plan_id) do
    plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(plans, &(Atom.to_string(&1.id) == plan_id)) do
      nil -> {:error, :invalid_plan}
      plan -> {:ok, plan}
    end
  end

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end
end
