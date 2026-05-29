defmodule YscWeb.Workers.CreateStripeCustomerWorker do
  @moduledoc """
  Oban worker that creates a Stripe customer for a user.

  Enqueued after registration so the Stripe customer exists when the user
  visits settings (e.g. membership or payment method). Idempotent: skips
  if the user already has a stripe_id.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:user_id],
      states: :incomplete,
      period: 60
    ]

  alias Ysc.Accounts.User
  alias Ysc.Customers
  alias Ysc.Repo

  @impl Oban.Worker
  @dialyzer {:nowarn_function, perform: 1}
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Repo.get(User, user_id) do
      nil ->
        Ysc.Logging.warning("User not found for CreateStripeCustomerWorker",
          user_id: user_id
        )

        :ok

      %User{stripe_id: stripe_id} when is_binary(stripe_id) ->
        # Already has Stripe customer
        :ok

      user ->
        case Customers.create_stripe_customer(user) do
          {:ok, _stripe_customer} ->
            Ysc.Logging.info("Created Stripe customer for user",
              user_id: user.id
            )

            :ok

          {:error, reason} ->
            Ysc.Logging.warning("Failed to create Stripe customer for user",
              user_id: user.id,
              error: inspect(reason)
            )

            {:error, reason}
        end
    end
  end
end
