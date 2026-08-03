defmodule YscWeb.Workers.WelcomeEmailWorker do
  @moduledoc """
  Oban worker for sending the new-member welcome email, 3 days after a
  member's first membership payment clears.

  Only fires for genuinely new members: skips WP-migrated accounts
  (`Accounts.wp_migrated?/1`) and re-checks that membership is still active
  at send time, in case it was cancelled/refunded in the 3-day window.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Accounts
  alias YscWeb.Emails.Notifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Accounts.get_user(user_id) do
      nil ->
        Ysc.Logging.warning("User not found for welcome email",
          user_id: user_id
        )

        :ok

      user ->
        cond do
          Accounts.wp_migrated?(user) ->
            Ysc.Logging.info("Skipping welcome email for WP-migrated user",
              user_id: user_id
            )

            :ok

          not Accounts.has_active_membership?(user) ->
            Ysc.Logging.info(
              "User no longer has an active membership, skipping welcome email",
              user_id: user_id
            )

            :ok

          true ->
            Notifier.deliver_welcome_email(user)
            :ok
        end
    end
  end

  @doc """
  Schedules the welcome email for 3 days from now.
  """
  def schedule_welcome_email(user_id) do
    %{"user_id" => user_id}
    |> new(schedule_in: 3 * 24 * 60 * 60)
    |> Oban.insert()
  end
end
