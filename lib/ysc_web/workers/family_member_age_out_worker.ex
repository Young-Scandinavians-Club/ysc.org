defmodule YscWeb.Workers.FamilyMemberAgeOutWorker do
  @moduledoc """
  Oban worker that runs daily to detach child family members who have turned 18.

  Family memberships cover children under 18. When a child sub-account turns 18
  they are removed from the family membership and emailed that they need their
  own membership to continue as a member.

  Only 18th birthdays within the last few days (club-local date) are picked up,
  so a missed run is caught on the next one. Detached members are no longer
  sub-accounts, so re-runs never process the same member twice.

  Pass `%{"lookback_days" => n}` in the job args to widen the window for a
  one-off backfill.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    today = club_today()

    opts =
      case args do
        %{"lookback_days" => days} when is_integer(days) and days >= 0 ->
          [lookback_days: days]

        _ ->
          []
      end

    members = Accounts.list_aged_out_family_members(today, opts)

    Ysc.Logging.info("Starting family member age-out check",
      date: today,
      count: length(members)
    )

    results =
      Enum.map(members, &Accounts.detach_aged_out_family_member/1)

    # Members who left their family since being listed come back as
    # {:error, :not_sub_account}; unexpected DB errors raise and Oban retries.
    detached_count = Enum.count(results, &match?({:ok, _}, &1))
    skipped_count = length(results) - detached_count

    Ysc.Logging.info("Family member age-out check complete",
      detached_count: detached_count,
      skipped_count: skipped_count
    )

    :ok
  end

  defp club_today do
    tz = Application.get_env(:ysc, :default_timezone, "America/Los_Angeles")

    tz
    |> DateTime.now!()
    |> DateTime.to_date()
  end
end
