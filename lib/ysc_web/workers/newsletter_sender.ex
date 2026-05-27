defmodule YscWeb.Workers.NewsletterSender do
  @moduledoc """
  Oban worker for sending a newsletter edition to all subscribed subscribers.

  Performs: load edition (with cover_image), load posts and events by id,
  list subscribers (subscribed: true), render and send one email per subscriber,
  then update edition to :sent with sent_at and sent_count.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :mailers,
    max_attempts: 3,
    unique: [
      keys: [:edition_id],
      states: [:available, :scheduled, :executing, :retryable],
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

    sent_count =
      Task.async_stream(
        subscribers,
        fn subscriber ->
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
            subscriber_id: subscriber.id
          }

          case Messages.run_send_message_idempotent(email, idempotency_attrs) do
            {:ok, _} ->
              1

            {:error, reason} ->
              Ysc.Logging.warning("NewsletterSender: failed to send",
                email: subscriber.email,
                reason: inspect(reason)
              )

              0
          end
        end,
        max_concurrency: 5,
        timeout: 30_000
      )
      |> Enum.reduce(0, fn {:ok, n}, acc -> acc + n end)

    attrs = %{
      status: :sent,
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
      sent_count: sent_count
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
          sent_count: sent_count,
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
