defmodule YscWeb.Workers.WelcomeEmailWorker do
  @moduledoc """
  Oban worker for sending the new-member welcome email, 7 days after a
  member's first membership payment clears.
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
        if Accounts.has_active_membership?(user) do
          Notifier.deliver_welcome_email(user)
          :ok
        else
          Ysc.Logging.info(
            "User no longer has an active membership, skipping welcome email",
            user_id: user_id
          )

          :ok
        end
    end
  end

  @doc """
  Schedules the welcome email for 7 days from now.
  """
  def schedule_welcome_email(user_id) do
    %{"user_id" => user_id}
    |> new(schedule_in: 7 * 24 * 60 * 60)
    |> Oban.insert()
  end
end
