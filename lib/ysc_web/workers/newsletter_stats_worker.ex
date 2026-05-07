defmodule YscWeb.Workers.NewsletterStatsWorker do
  @moduledoc """
  Oban worker that sends newsletter stats snapshot 24 hours after newsletter is sent.

  Gathers engagement metrics (opens, clicks, bounces, complaints) and sends a
  summary email to info@ysc.org.
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
  alias Ysc.Mailer

  import Swoosh.Email

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    edition_id = args["edition_id"] || args[:edition_id]

    if is_nil(edition_id) do
      Ysc.Logging.warning("NewsletterStatsWorker: missing edition_id", args: args)
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

    html_body = build_html_body(edition, stats)
    text_body = build_text_body(edition, stats)

    recipient = Ysc.EmailConfig.contact_email()

    email =
      new()
      |> to(recipient)
      |> from({Ysc.EmailConfig.from_name(), Ysc.EmailConfig.from_email()})
      |> subject("[YSC Newsletter Stats] #{edition.title}")
      |> html_body(html_body)
      |> text_body(text_body)

    case Mailer.deliver(email) do
      {:ok, _} ->
        Ysc.Logging.info("NewsletterStatsWorker: stats email sent",
          edition_id: edition.id,
          recipient: recipient
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error("NewsletterStatsWorker: failed to send stats email",
          edition_id: edition.id,
          recipient: recipient,
          error: inspect(reason)
        )

        {:error, reason}
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
      top_links: Enum.take(top_links, 5)
    }
  end

  defp build_html_body(edition, stats) do
    sent_at_formatted = format_datetime(edition.sent_at)
    open_rate = calculate_rate(stats.opens, stats.sent_count)
    click_rate = calculate_rate(stats.clicks, stats.sent_count)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
          line-height: 1.6;
          color: #333;
          max-width: 600px;
          margin: 0 auto;
          padding: 20px;
        }
        h1 {
          color: #2c5282;
          border-bottom: 2px solid #3182ce;
          padding-bottom: 10px;
        }
        h2 {
          color: #2d3748;
          margin-top: 30px;
        }
        .stats-grid {
          display: grid;
          grid-template-columns: repeat(2, 1fr);
          gap: 15px;
          margin: 20px 0;
        }
        .stat-card {
          background: #f7fafc;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          padding: 15px;
        }
        .stat-label {
          font-size: 14px;
          color: #718096;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .stat-value {
          font-size: 32px;
          font-weight: bold;
          color: #2d3748;
          margin-top: 5px;
        }
        .stat-subtext {
          font-size: 14px;
          color: #718096;
          margin-top: 5px;
        }
        .links-list {
          list-style: none;
          padding: 0;
        }
        .links-list li {
          background: #f7fafc;
          border: 1px solid #e2e8f0;
          border-radius: 6px;
          padding: 12px;
          margin-bottom: 10px;
        }
        .link-clicks {
          font-weight: bold;
          color: #3182ce;
        }
        .link-url {
          color: #718096;
          font-size: 14px;
          word-break: break-all;
          margin-top: 5px;
        }
        .link-title {
          color: #2d3748;
          font-size: 16px;
          margin-top: 5px;
        }
        .metadata {
          background: #edf2f7;
          border-left: 4px solid #3182ce;
          padding: 15px;
          margin: 20px 0;
        }
        .metadata p {
          margin: 5px 0;
        }
      </style>
    </head>
    <body>
      <h1>Newsletter Stats Snapshot</h1>
      
      <div class="metadata">
        <p><strong>Newsletter:</strong> #{html_escape(edition.title)}</p>
        <p><strong>Subject:</strong> #{html_escape(edition.subject)}</p>
        <p><strong>Sent at:</strong> #{sent_at_formatted}</p>
      </div>

      <h2>Engagement Metrics</h2>
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-label">Sent</div>
          <div class="stat-value">#{stats.sent_count}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Opens</div>
          <div class="stat-value">#{stats.opens}</div>
          <div class="stat-subtext">#{open_rate}% open rate</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Clicks</div>
          <div class="stat-value">#{stats.clicks}</div>
          <div class="stat-subtext">#{click_rate}% click rate</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Bounces</div>
          <div class="stat-value">#{stats.bounces}</div>
        </div>
      </div>
      
      #{if stats.complaints > 0 do
        """
        <div class="stat-card" style="border-color: #fc8181; margin-top: 15px;">
          <div class="stat-label" style="color: #c53030;">Complaints</div>
          <div class="stat-value" style="color: #c53030;">#{stats.complaints}</div>
        </div>
        """
      else
        ""
      end}

      #{if stats.top_links != [] do
        """
        <h2>Top Clicked Links</h2>
        <ul class="links-list">
          #{Enum.map_join(stats.top_links, "\n", fn link ->
            """
            <li>
              <span class="link-clicks">#{link.clicks} clicks</span>
              #{if link.title do
                ~s(<div class="link-title">#{html_escape(link.title)}</div>)
              else
                ""
              end}
              <div class="link-url">#{html_escape(link.url)}</div>
            </li>
            """
          end)}
        </ul>
        """
      else
        ""
      end}
      
      <p style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #e2e8f0; color: #718096; font-size: 14px;">
        This stats snapshot was generated 24 hours after the newsletter was sent.
      </p>
    </body>
    </html>
    """
  end

  defp build_text_body(edition, stats) do
    sent_at_formatted = format_datetime(edition.sent_at)
    open_rate = calculate_rate(stats.opens, stats.sent_count)
    click_rate = calculate_rate(stats.clicks, stats.sent_count)

    links_section =
      if stats.top_links != [] do
        links_text =
          Enum.map_join(stats.top_links, "\n", fn link ->
            title_line = if link.title, do: "\n  #{link.title}", else: ""
            "  #{link.clicks} clicks#{title_line}\n  #{link.url}"
          end)

        "\n\nTop Clicked Links:\n#{links_text}"
      else
        ""
      end

    complaints_section =
      if stats.complaints > 0 do
        "\n\n⚠️  Complaints: #{stats.complaints}"
      else
        ""
      end

    """
    Newsletter Stats Snapshot
    ========================

    Newsletter: #{edition.title}
    Subject: #{edition.subject}
    Sent at: #{sent_at_formatted}

    Engagement Metrics
    ------------------
    Sent: #{stats.sent_count}
    Opens: #{stats.opens} (#{open_rate}%)
    Clicks: #{stats.clicks} (#{click_rate}%)
    Bounces: #{stats.bounces}#{complaints_section}#{links_section}

    ---
    This stats snapshot was generated 24 hours after the newsletter was sent.
    """
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp calculate_rate(_count, 0), do: "0.0"

  defp calculate_rate(count, total) do
    rate = count / total * 100
    :erlang.float_to_binary(rate, decimals: 1)
  end

  defp html_escape(nil), do: ""

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp html_escape(_), do: ""
end
