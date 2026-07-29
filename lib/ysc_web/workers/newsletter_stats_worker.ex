defmodule YscWeb.Workers.NewsletterStatsWorker do
  @moduledoc """
  Oban worker that sends newsletter stats snapshot 24 hours after newsletter is sent.

  Gathers engagement metrics (opens, clicks, bounces, complaints) and sends a
  summary email to info@ysc.org.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :transactional_mail,
    max_attempts: 3,
    unique: [
      keys: [:edition_id],
      states: :incomplete,
      period: :infinity
    ]

  alias Ysc.Repo
  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias YscWeb.Emails.NewsletterStatsSnapshot
  alias YscWeb.Emails.Notifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    edition_id = args["edition_id"] || args[:edition_id]

    if is_nil(edition_id) do
      Ysc.Logging.warning("NewsletterStatsWorker: missing edition_id",
        args: args
      )

      :ok
    else
      case Repo.get(Edition, edition_id) do
        nil ->
          Ysc.Logging.warning("NewsletterStatsWorker: edition not found",
            edition_id: edition_id
          )

          :ok

        edition ->
          if edition.status == :sent do
            send_stats_email(edition)
          else
            Ysc.Logging.info(
              "NewsletterStatsWorker: edition not sent, skipping stats",
              edition_id: edition_id,
              status: edition.status
            )

            :ok
          end
      end
    end
  end

  defp send_stats_email(edition) do
    stats = gather_stats(edition)
    assigns = NewsletterStatsSnapshot.build_assigns(edition, stats)
    text_body = NewsletterStatsSnapshot.build_text_body(edition, stats)
    recipient = Ysc.EmailConfig.contact_email()
    template_name = NewsletterStatsSnapshot.get_template_name()
    idempotency_key = "newsletter_stats_snapshot_#{edition.id}"

    case Notifier.schedule_email(
           recipient,
           idempotency_key,
           NewsletterStatsSnapshot.get_subject(edition),
           template_name,
           assigns,
           text_body
         ) do
      %Oban.Job{} = job ->
        Ysc.Logging.info("NewsletterStatsWorker: stats email scheduled",
          edition_id: edition.id,
          recipient: recipient,
          job_id: job.id
        )

        :ok

      {:error, reason} = error ->
        Ysc.Logging.error(
          "NewsletterStatsWorker: failed to schedule stats email",
          edition_id: edition.id,
          recipient: recipient,
          error: inspect(reason)
        )

        error
    end
  end

  defp gather_stats(edition) do
    event_counts = Newsletter.count_email_events_by_type(edition.id)
    top_links = Newsletter.count_clicks_by_link(edition.id)

    %{
      sent_count: edition.sent_count || 0,
      opens: Map.get(event_counts, "open", 0),
      clicks: Map.get(event_counts, "click", 0),
      bounces: Map.get(event_counts, "bounce", 0),
      complaints: Map.get(event_counts, "complaint", 0),
      top_links: Enum.map(Enum.take(top_links, 5), &top_link_assigns/1)
    }
  end

  defp top_link_assigns(link) do
    %{
      url: link.url,
      clicks: link.clicks,
      title: link.title
    }
  end
end
