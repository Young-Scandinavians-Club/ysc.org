defmodule Ysc.WpMigration.NewsletterCsvImport do
  @moduledoc """
  Imports Mailchimp/Emailable newsletter CSV rows into `newsletter_subscribers`.

  Imports rows with List status `subscribed` and Global status `subscribed`.
  Existing subscribers are left subscribed (idempotent); names/user links are
  filled in when missing. MX/disposable checks are skipped for this trusted
  historical list.
  """

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Accounts.Email
  alias Ysc.Newsletter
  alias Ysc.Newsletter.Subscriber

  @source "wp_newsletter_csv"

  @doc """
  Imports newsletter subscribers from a CSV file.

  Options:
  - `:dry_run` — count only, no writes (default: false)

  Returns `{:ok, stats}` where stats includes `:created`, `:updated`,
  `:unchanged`, `:skipped`, `:failed`, and `:failures`.
  """
  def run(csv_path, opts \\ []) when is_binary(csv_path) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    with {:ok, rows} <- read_csv(csv_path) do
      eligible = Enum.filter(rows, &active_subscriber?/1)

      Ysc.Logging.info(
        "[Newsletter CSV] Importing #{length(eligible)} active of #{length(rows)} rows" <>
          if(dry_run?, do: " (dry run)", else: "")
      )

      stats =
        Enum.reduce(eligible, empty_stats(), fn row, acc ->
          import_row(row, dry_run?, acc)
        end)

      Ysc.Logging.info(
        "[Newsletter CSV] Done created=#{stats.created} updated=#{stats.updated} " <>
          "unchanged=#{stats.unchanged} skipped=#{stats.skipped} failed=#{stats.failed}"
      )

      {:ok, stats}
    end
  end

  defp empty_stats do
    %{
      created: 0,
      updated: 0,
      unchanged: 0,
      skipped: 0,
      failed: 0,
      failures: []
    }
  end

  defp read_csv(path) do
    if File.exists?(path) do
      rows =
        path
        |> File.stream!()
        |> Stream.map(&strip_bom/1)
        |> CSV.decode!(headers: true)
        |> Enum.to_list()

      {:ok, rows}
    else
      {:error, "CSV not found: #{path}"}
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(line), do: line

  defp active_subscriber?(row) do
    list_status = String.downcase(String.trim(row["List status"] || ""))
    global_status = String.downcase(String.trim(row["Global status"] || ""))
    list_status == "subscribed" and global_status == "subscribed"
  end

  defp import_row(row, dry_run?, stats) do
    email = row["Email"] |> to_string() |> String.trim()

    if email == "" do
      %{stats | skipped: stats.skipped + 1}
    else
      do_import_row(email, row, dry_run?, stats)
    end
  end

  defp do_import_row(email, row, dry_run?, stats) do
    normalized = Email.normalize(email)
    existing = Newsletter.get_subscriber_by_email(normalized)
    user = Accounts.get_user_by_email(normalized)

    cond do
      dry_run? ->
        cond do
          is_nil(existing) -> %{stats | created: stats.created + 1}
          existing.subscribed -> %{stats | unchanged: stats.unchanged + 1}
          true -> %{stats | updated: stats.updated + 1}
        end

      true ->
        opts = subscribe_opts(row, user, existing)

        case Newsletter.subscribe(normalized, opts) do
          {:ok, %Subscriber{} = subscriber} ->
            classify_success(stats, existing, subscriber)

          {:error, reason} ->
            Ysc.Logging.warning(
              "[Newsletter CSV] Failed to import #{normalized}: #{inspect(reason)}"
            )

            %{
              stats
              | failed: stats.failed + 1,
                failures: [
                  %{email: normalized, reason: inspect(reason)} | stats.failures
                ]
            }
        end
    end
  end

  defp subscribe_opts(row, user, existing) do
    csv_first = blank_to_nil(row["First name"])
    csv_last = blank_to_nil(row["Last name"])
    subscribed_at = parse_subscription_time(row["Subscription time"])

    metadata = %{
      "wp_newsletter_csv" => true,
      "list_status" => row["List status"],
      "global_status" => row["Global status"]
    }

    # Prefer existing names; only fill blanks from the CSV.
    first_name =
      if existing && present?(existing.first_name),
        do: nil,
        else: csv_first

    last_name =
      if existing && present?(existing.last_name),
        do: nil,
        else: csv_last

    opts = [
      source: @source,
      skip_email_validation: true,
      first_name: first_name,
      last_name: last_name,
      metadata: metadata
    ]

    opts =
      if user,
        do: Keyword.put(opts, :user_id, user.id),
        else: opts

    # Only set historical subscribed_at for new rows or reactivations
    if is_nil(existing) or not existing.subscribed do
      Keyword.put(opts, :subscribed_at, subscribed_at)
    else
      opts
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp classify_success(stats, nil, _subscriber) do
    %{stats | created: stats.created + 1}
  end

  defp classify_success(stats, %Subscriber{subscribed: false}, _subscriber) do
    %{stats | updated: stats.updated + 1}
  end

  defp classify_success(stats, %Subscriber{}, _subscriber) do
    %{stats | unchanged: stats.unchanged + 1}
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp parse_subscription_time(nil), do: default_subscribed_at()
  defp parse_subscription_time(""), do: default_subscribed_at()

  defp parse_subscription_time(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed in ["", "0000-00-00 00:00:00"] ->
        default_subscribed_at()

      true ->
        normalized = String.replace(trimmed, " ", "T")

        case NaiveDateTime.from_iso8601(normalized) do
          {:ok, ndt} ->
            DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.truncate(:second)

          _ ->
            default_subscribed_at()
        end
    end
  end

  defp parse_subscription_time(_), do: default_subscribed_at()

  defp default_subscribed_at do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
