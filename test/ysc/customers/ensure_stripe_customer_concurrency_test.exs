defmodule Ysc.Customers.EnsureStripeCustomerConcurrencyTest do
  @moduledoc """
  Regression tests for concurrent `Customers.ensure_stripe_customer/1` calls.

  Without the per-user advisory lock, two callers that both see `stripe_id: nil`
  can each create a Stripe customer; whichever persist wins orphans the other and
  can strand subscriptions or renewal payments on the wrong customer.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.User
  alias Ysc.Customers
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "ensure_stripe_customer/1 concurrency" do
    test "concurrent calls create only one Stripe customer and share stripe_id",
         %{sandbox_owner: owner} do
      user = user_fixture()

      {:ok, user} =
        user
        |> User.update_user_changeset(%{stripe_id: nil})
        |> Repo.update()

      create_count = :counters.new(1, [:atomics])

      Mox.stub(Stripe.CustomerMock, :create, fn params, opts ->
        :counters.add(create_count, 1, 1)

        user_id =
          case params do
            %{metadata: %{user_id: id}} -> id
            %{"metadata" => %{"user_id" => id}} -> id
            _ -> nil
          end

        assert opts[:idempotency_key] == "customer_create_#{user_id}"

        {:ok,
         %Stripe.Customer{
           id: "cus_concurrent_#{user_id}",
           email: Map.get(params, :email) || Map.get(params, "email")
         }}
      end)

      results =
        1..6
        |> Enum.map(fn _ ->
          Task.async(fn ->
            allow_sandbox(self(), owner)
            Customers.ensure_stripe_customer(user)
          end)
        end)
        |> Task.await_many(15_000)

      stripe_ids = Enum.map(results, & &1.stripe_id) |> Enum.uniq()

      assert length(stripe_ids) == 1
      assert hd(stripe_ids) == "cus_concurrent_#{user.id}"
      assert :counters.get(create_count, 1) == 1
      assert Repo.reload!(user).stripe_id == hd(stripe_ids)
    end
  end
end
