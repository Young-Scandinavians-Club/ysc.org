defmodule YscWeb.Workers.SeasonWeekendAvailabilityWorker do
  @moduledoc """
  Daily check: sends a one-time "first bookable weekend" announcement email
  when the Tahoe cabin's booking window reaches the first Friday-check-in,
  Sunday-check-out weekend of the upcoming Winter or Summer season.

  - Winter: rooms-only (buyout is never available for winter nights), so this
    announces room booking availability.
  - Summer: announces that a whole-cabin buyout is now available for that
    weekend.

  Each season occurrence is notified at most once, tracked via
  `weekend_notification_sent_cycle_year` on the season row (keyed by the
  resolved occurrence's start year, so the same recurring season row can fire
  again for next year's occurrence without any reset needed).

  Run daily via Oban Cron rather than a single precomputed `scheduled_at`, so
  it stays correct if an admin edits `advance_booking_days` after the fact —
  see `Ysc.Bookings.SeasonHelpers.first_weekend_booking_window/4` for the
  actual bookability check.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Ysc.Accounts
  alias Ysc.Bookings
  alias Ysc.Bookings.SeasonCache
  alias Ysc.Bookings.SeasonHelpers

  alias YscWeb.Emails.{
    Notifier,
    TahoeSummerBuyoutAvailable,
    TahoeWinterWeekendAvailable
  }

  alias YscWeb.Emails.Helpers, as: EmailHelpers

  @property :tahoe

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    run()
  end

  @doc """
  Runs the check for a given `today` (defaults to the real cabin-local date).

  Exposed separately from `perform/1` so tests can inject a fixed date
  instead of depending on the real wall clock.
  """
  def run(today \\ SeasonHelpers.cabin_today()) do
    seasons = SeasonCache.get_all_for_property(@property)

    maybe_notify("Winter", seasons, today, TahoeWinterWeekendAvailable)
    maybe_notify("Summer", seasons, today, TahoeSummerBuyoutAvailable)

    :ok
  end

  defp maybe_notify(season_name, seasons, today, email_module) do
    case SeasonHelpers.first_weekend_booking_window(
           @property,
           seasons,
           today,
           season_name
         ) do
      %{open?: true, season: season, cycle_year: cycle_year} = window ->
        # Cached seasons omit notification bookkeeping updates (see
        # `Bookings.mark_weekend_notification_sent/3`), so reload before the
        # idempotency check to avoid duplicate sends within the cache TTL.
        season = Bookings.get_season!(season.id)

        if season.weekend_notification_sent_cycle_year == cycle_year do
          :ok
        else
          send_blast(%{window | season: season}, email_module)
        end

      _ ->
        :ok
    end
  end

  defp send_blast(
         %{
           season: season,
           weekend_checkin: checkin,
           weekend_checkout: checkout,
           cycle_year: cycle_year
         },
         email_module
       ) do
    cycle_label = cycle_label(season, cycle_year)
    recipients = notification_recipients()

    Ysc.Logging.info("Sending season weekend availability notification",
      season: season.name,
      cycle_year: cycle_year,
      weekend_checkin: checkin,
      recipient_count: length(recipients)
    )

    template_name = email_module.get_template_name()
    subject = email_module.get_subject(cycle_label)
    reply_to = Ysc.EmailConfig.booking_reply_to(:tahoe)

    shared =
      email_module.prepare_email_data(checkin, checkout, cycle_label, %{
        first_name: nil
      })
      |> Map.delete(:first_name)

    inserted =
      recipients
      |> Enum.map(fn user ->
        %{
          recipient: user.email,
          idempotency_key:
            "#{template_name}_#{season.id}_#{cycle_year}_#{user.id}",
          subject: subject,
          template: template_name,
          variables:
            Map.put(
              shared,
              :first_name,
              EmailHelpers.member_greeting_name(user)
            ),
          text_body: "",
          user_id: user.id,
          opts: [reply_to: reply_to]
        }
      end)
      |> Notifier.schedule_emails()

    success_count = length(inserted)

    case Bookings.mark_weekend_notification_sent(
           season,
           cycle_year,
           success_count
         ) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Ysc.Logging.error("Failed to mark weekend notification sent",
          season_id: season.id,
          errors: inspect(changeset.errors)
        )

        {:error, :db_update_failed}
    end
  end

  defp cycle_label(%{name: "Winter"}, cycle_year),
    do: "#{cycle_year}/#{cycle_year + 1}"

  defp cycle_label(_season, cycle_year), do: "#{cycle_year}"

  defp notification_recipients do
    Accounts.list_event_notification_recipients()
  end
end
