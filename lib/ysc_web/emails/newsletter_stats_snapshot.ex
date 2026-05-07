defmodule YscWeb.Emails.NewsletterStatsSnapshot do
  @moduledoc """
  MJML email template for the post-send newsletter stats snapshot.
  """

  use MjmlEEx,
    mjml_template: "templates/newsletter_stats_snapshot.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name do
    "newsletter_stats_snapshot"
  end

  def get_subject(edition) do
    "[YSC Newsletter Stats] #{edition.title}"
  end

  def build_assigns(edition, stats) do
    sent_count = stats.sent_count || 0
    opens = stats.opens || 0
    clicks = stats.clicks || 0
    bounces = stats.bounces || 0
    complaints = stats.complaints || 0

    %{
      edition_title: edition.title,
      edition_subject: edition.subject,
      sent_at: format_datetime(edition.sent_at),
      metrics: [
        %{
          label: "Sent",
          value: sent_count,
          helper: nil,
          color: "#0f172a",
          background: "#f8fafc",
          border: "#e2e8f0"
        },
        %{
          label: "Unique opens",
          value: opens,
          helper: "#{calculate_rate(opens, sent_count)}% open rate",
          color: "#1447e6",
          background: "#eff6ff",
          border: "#bfdbfe"
        },
        %{
          label: "Unique clicks",
          value: clicks,
          helper: "#{calculate_rate(clicks, sent_count)}% click rate",
          color: "#047857",
          background: "#ecfdf5",
          border: "#bbf7d0"
        },
        %{
          label: "Bounces",
          value: bounces,
          helper: nil,
          color: "#b45309",
          background: "#fffbeb",
          border: "#fde68a"
        }
      ],
      complaints: complaints,
      has_complaints: complaints > 0,
      top_links: stats.top_links || [],
      has_top_links: (stats.top_links || []) != []
    }
  end

  def build_text_body(edition, stats) do
    sent_count = stats.sent_count || 0
    opens = stats.opens || 0
    clicks = stats.clicks || 0
    bounces = stats.bounces || 0
    complaints = stats.complaints || 0
    top_links = stats.top_links || []

    links_section =
      if top_links != [] do
        links_text =
          Enum.map_join(top_links, "\n", fn link ->
            title_line = if link.title, do: "\n  #{link.title}", else: ""
            "  #{link.clicks} clicks#{title_line}\n  #{link.url}"
          end)

        "\n\nTop Clicked Links:\n#{links_text}"
      else
        ""
      end

    complaints_section =
      if complaints > 0 do
        "\nComplaints: #{complaints}"
      else
        ""
      end

    """
    Newsletter Stats Snapshot
    ========================

    Newsletter: #{edition.title}
    Subject: #{edition.subject}
    Sent at: #{format_datetime(edition.sent_at)}

    Engagement Metrics
    ------------------
    Sent: #{sent_count}
    Unique opens: #{opens} (#{calculate_rate(opens, sent_count)}%)
    Unique clicks: #{clicks} (#{calculate_rate(clicks, sent_count)}%)
    Bounces: #{bounces}#{complaints_section}#{links_section}

    ---
    This stats snapshot was generated 24 hours after the newsletter was sent.
    """
  end

  def format_datetime(nil), do: "N/A"

  def format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end

  def calculate_rate(_count, 0), do: "0.0"

  def calculate_rate(count, total) do
    count
    |> Kernel./(total)
    |> Kernel.*(100)
    |> :erlang.float_to_binary(decimals: 1)
  end
end
