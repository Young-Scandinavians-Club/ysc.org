defmodule YscWeb.Workers.NewsletterSender do
  @moduledoc """
  Oban worker for sending a newsletter edition to all subscribed subscribers.

  Performs: load edition (with cover_image), load posts and events by id,
  list subscribers (subscribed: true), render and send one email per subscriber,
  then update edition to :sent with sent_at and sent_count.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :bulk_mail,
    max_attempts: 100,
    unique: [
      keys: [:edition_id],
      states: :incomplete,
      period: :infinity
    ]

  alias Ysc.Repo
  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias Ysc.Messages
  alias Ysc.Posts
  alias Ysc.Events
  alias YscWeb.Emails.NewsletterEdition

  import Swoosh.Email

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    edition_id = args["edition_id"] || args[:edition_id]

    if is_nil(edition_id) do
      Ysc.Logging.warning("NewsletterSender: missing edition_id", args: args)
      :ok
    else
      case Repo.get(Edition, edition_id) do
        nil ->
          Ysc.Logging.warning("NewsletterSender: edition not found",
            edition_id: edition_id
          )

          :ok

        edition ->
          if edition.status in [:draft, :scheduled, :sending] do
            send_to_subscribers(edition)
          else
            Ysc.Logging.info(
              "NewsletterSender: edition already sent or invalid, skipping",
              edition_id: edition_id,
              status: edition.status
            )

            :ok
          end
      end
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    cap = min((60 * :math.pow(2, min(attempt, 8))) |> trunc(), 60 * 60)
    :rand.uniform(max(cap, 1))
  end

  if Ysc.Env.dev?() do
    defp maybe_dev_delay, do: Process.sleep(8_000)
  else
    defp maybe_dev_delay, do: :ok
  end

  defp send_to_subscribers(edition) do
    maybe_dev_delay()
    edition = Repo.preload(edition, :cover_image)
    post_ids = edition.post_ids || []
    event_ids = edition.event_ids || []

    posts = Posts.list_posts_by_ids(post_ids, [:featured_image])

    events =
      Events.list_events_by_ids(event_ids,
        preloads: [:cover_image, :ticket_tiers]
      )

    subscribers = Newsletter.list_subscribers(subscribed: true)

    pending_subscribers =
      Newsletter.subscribers_needing_newsletter_delivery(edition, subscribers)

    result =
      Enum.reduce_while(pending_subscribers, %{failures: 0}, fn subscriber,
                                                                acc ->
        case send_to_subscriber(edition, subscriber, posts, events) do
          :ok ->
            pace_next_delivery()
            {:cont, acc}

          {:snooze, seconds} ->
            {:halt, {:snooze, seconds, acc.failures}}

          {:error, reason} ->
            Ysc.Logging.warning("NewsletterSender: failed to send",
              email: subscriber.email,
              reason: inspect(reason)
            )

            pace_next_delivery()
            {:cont, %{acc | failures: acc.failures + 1}}
        end
      end)

    case Newsletter.record_edition_delivery_progress(edition, subscribers) do
      {:ok, _updated_edition} ->
        :ok

      {:error, reason} ->
        Ysc.Logging.warning(
          "NewsletterSender: failed to record delivery progress",
          edition_id: edition.id,
          reason: inspect(reason)
        )
    end

    handle_send_result(result, edition, posts, events, subscribers)
  end

  defp send_to_subscriber(edition, subscriber, posts, events) do
    assigns =
      NewsletterEdition.build_assigns(edition, subscriber, posts, events)

    html = NewsletterEdition.render(assigns)

    email =
      new()
      |> to(subscriber.email)
      |> from({Ysc.EmailConfig.from_name(), Ysc.EmailConfig.from_email()})
      |> subject("[YSC] #{edition.subject}")
      |> html_body(html)
      |> text_body(plain_text_fallback(edition))

    idempotency_attrs = %{
      message_type: :email,
      idempotency_key: "newsletter_#{edition.id}_#{subscriber.id}",
      message_template: "newsletter_edition",
      params: %{edition_id: edition.id},
      email: subscriber.email,
      user_id: subscriber.user_id,
      rendered_message: html,
      edition_id: edition.id,
      subscriber_id: subscriber.id,
      delivery_retry: true
    }

    case Messages.run_send_message_idempotent(email, idempotency_attrs) do
      {:ok, _} -> :ok
      {:error, {:snooze, seconds}} -> {:snooze, seconds}
      {:error, {:delivery, %{category: :rate_limited}}} -> {:snooze, 15}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_send_result(
         {:snooze, seconds, 0},
         _edition,
         _posts,
         _events,
         _subscribers
       ),
       do: {:snooze, seconds}

  defp handle_send_result(
         {:snooze, _seconds, failures},
         edition,
         _posts,
         _events,
         _subscribers
       ) do
    log_incomplete_delivery(edition, failures)
    {:error, {:incomplete_delivery, failures}}
  end

  defp handle_send_result(%{failures: 0}, edition, posts, events, subscribers),
    do: complete_newsletter_delivery(edition, posts, events, subscribers)

  defp handle_send_result(
         %{failures: failures},
         edition,
         _posts,
         _events,
         _subscribers
       ) do
    log_incomplete_delivery(edition, failures)
    {:error, {:incomplete_delivery, failures}}
  end

  defp log_incomplete_delivery(edition, failed_count) do
    Ysc.Logging.warning("NewsletterSender: retrying incomplete delivery",
      edition_id: edition.id,
      failed_count: failed_count
    )
  end

  defp pace_next_delivery do
    case Application.get_env(:ysc, :newsletter_send_interval_ms, 0) do
      interval when is_integer(interval) and interval > 0 ->
        Process.sleep(interval)

      _ ->
        :ok
    end
  end

  defp complete_newsletter_delivery(edition, posts, events, subscribers) do
    attrs = %{
      status: :sent,
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
      sent_count: length(subscribers)
    }

    case Newsletter.update_edition(edition, attrs) do
      {:ok, sent_edition} ->
        archive_html =
          NewsletterEdition.render(
            NewsletterEdition.build_archive_assigns(sent_edition, posts, events)
          )

        case Newsletter.store_archive_html(sent_edition, archive_html) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Ysc.Logging.error("NewsletterSender: failed to store archive HTML",
              edition_id: edition.id,
              error: inspect(reason)
            )

            :ok
        end

        Newsletter.broadcast_edition_sent(Repo.preload(sent_edition, :creator))

        # Schedule stats email to be sent 24 hours after newsletter was sent
        schedule_stats_email(sent_edition)

        Ysc.Logging.info("NewsletterSender: completed",
          edition_id: edition.id,
          sent_count: length(subscribers),
          subscriber_count: length(subscribers)
        )

        :ok

      {:error, reason} ->
        # Emails were already delivered (idempotency key prevents re-sends).
        # Log and return :ok so Oban does not retry — a retry cannot undo
        # the sends and would only waste attempts.
        Ysc.Logging.error("NewsletterSender: failed to mark edition as sent",
          edition_id: edition.id,
          attrs: inspect(attrs),
          error: inspect(reason)
        )

        :ok
    end
  end

  defp plain_text_fallback(edition) do
    [
      edition.title,
      edition.intro_text,
      "",
      "View online and manage subscription:",
      ""
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join("\n")
  end

  defp schedule_stats_email(edition) do
    # Schedule stats email 24 hours after the newsletter was sent
    scheduled_at =
      edition.sent_at
      |> DateTime.add(24, :hour)
      |> DateTime.truncate(:second)

    %{edition_id: edition.id}
    |> YscWeb.Workers.NewsletterStatsWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Ysc.Logging.info("NewsletterSender: scheduled stats email",
          edition_id: edition.id,
          scheduled_at: scheduled_at
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error("NewsletterSender: failed to schedule stats email",
          edition_id: edition.id,
          error: inspect(reason)
        )

        :ok
    end
  end
end
