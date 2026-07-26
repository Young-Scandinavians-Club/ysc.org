defmodule Ysc.WpMigration.ReconcileCsvs do
  @moduledoc """
  Cross-checks a WordPress migration export against manual admin CSV exports
  under `wp_export_csvs/`.

  These CSVs are not pipeline inputs — they are a manual sanity check against
  WooCommerce / MPHB / user-list exports from the old site.
  """

  require Ysc.Logging

  alias Ysc.Accounts.Email
  alias Ysc.WpMigration.IgnoredAccounts

  @doc """
  Compare export JSON counts/sets to admin CSVs.

  Options:
  - `:export_dir` (required)
  - `:csv_dir` (default: `"wp_export_csvs"`)
  - `:print` (default: `true`) — set to `false` in tests to suppress stdout

  Returns `{:ok, report}` or `{:error, reason}`. Prints a human-readable report when
  `:print` is true.
  """
  def run(opts \\ []) do
    export_dir = opts[:export_dir]
    csv_dir = Path.expand(opts[:csv_dir] || "wp_export_csvs")

    cond do
      is_nil(export_dir) or export_dir == "" ->
        {:error, "Missing :export_dir"}

      not File.dir?(Path.expand(export_dir)) ->
        {:error, "Export directory not found: #{export_dir}"}

      not File.dir?(csv_dir) ->
        {:error, "CSV directory not found: #{csv_dir}"}

      true ->
        do_run(
          Path.expand(export_dir),
          csv_dir,
          Keyword.get(opts, :print, true)
        )
    end
  end

  defp do_run(export_dir, csv_dir, print?) do
    users = read_json(Path.join(export_dir, "users.json"))
    bookings = read_json(Path.join(export_dir, "bookings.json"))

    csv_users = read_csv(Path.join(csv_dir, "users.csv"))
    csv_memberships = read_csv(Path.join(csv_dir, "memberships.csv"))
    csv_subscriptions = read_csv(Path.join(csv_dir, "subscriptions.csv"))
    csv_bookings = read_csv(Path.join(csv_dir, "bookings.csv"))

    export_emails =
      users
      |> Enum.map(&normalize_email(&1["email"]))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    csv_emails =
      csv_users
      |> Enum.map(&normalize_email(&1["Email"] || &1["email"]))
      |> Enum.reject(&(is_nil(&1) or IgnoredAccounts.ignored_email?(&1)))
      |> MapSet.new()

    active_memberships_csv =
      Enum.count(csv_memberships, fn row ->
        status = String.downcase(to_string(row["membership_status"] || ""))
        status == "active"
      end)

    # Compare like-for-like with admin CSVs: wcm-active and wc-active only.
    # Load still treats wc-on-hold as auto-renew-capable; reported separately.
    active_memberships_export =
      Enum.count(users, fn row -> row["wcm_status"] == "wcm-active" end)

    active_subs_csv =
      Enum.count(csv_subscriptions, fn row ->
        String.downcase(to_string(row["Status"] || row["status"] || "")) ==
          "active"
      end)

    active_subs_export =
      Enum.count(users, fn row -> row["sub_status"] == "wc-active" end)

    on_hold_subs_export =
      Enum.count(users, fn row -> row["sub_status"] == "wc-on-hold" end)

    csv_bookings_confirmed =
      Enum.count(csv_bookings, fn row ->
        status =
          String.downcase(to_string(row["Status"] || row["status"] || ""))

        status in ["confirmed", "paid"]
      end)

    report = %{
      users: %{
        export: MapSet.size(export_emails),
        csv: MapSet.size(csv_emails),
        only_in_export:
          MapSet.difference(export_emails, csv_emails) |> MapSet.size(),
        only_in_csv:
          MapSet.difference(csv_emails, export_emails) |> MapSet.size()
      },
      active_memberships: %{
        export: active_memberships_export,
        csv: active_memberships_csv
      },
      active_subscriptions: %{
        export: active_subs_export,
        csv: active_subs_csv,
        on_hold_export: on_hold_subs_export
      },
      bookings: %{
        export: length(bookings),
        csv: length(csv_bookings),
        csv_confirmed: csv_bookings_confirmed
      }
    }

    if print?, do: print_report(report)

    {:ok, report}
  end

  defp print_report(report) do
    IO.puts("\n=== WP CSV reconcile (export vs wp_export_csvs) ===\n")

    print_pair(
      "Users (emails, ignored excluded from CSV)",
      report.users.export,
      report.users.csv
    )

    IO.puts(
      "  only_in_export=#{report.users.only_in_export}  only_in_csv=#{report.users.only_in_csv}"
    )

    print_pair(
      "Active memberships (wcm-active vs CSV active)",
      report.active_memberships.export,
      report.active_memberships.csv
    )

    print_pair(
      "Active subscriptions (wc-active vs CSV active)",
      report.active_subscriptions.export,
      report.active_subscriptions.csv
    )

    IO.puts(
      "  export wc-on-hold (auto-renew capable, not in CSV active): #{report.active_subscriptions.on_hold_export}"
    )

    print_pair(
      "Bookings (export future confirmed vs CSV all)",
      report.bookings.export,
      report.bookings.csv
    )

    IO.puts("  csv confirmed/paid (approx): #{report.bookings.csv_confirmed}")

    IO.puts("""

    Notes:
    - Counts are expected to be close, not always exact (ignored accounts,
      blank emails, status filters, extract rules, backup vs CSV export time).
    - CSV Auto Renewal column is often empty; export uses WP subscription status.
    - bookings.json is future confirmed MPHB bookings; bookings.csv is usually
      the full historical export (much larger).
    """)
  end

  defp print_pair(label, export_count, csv_count) do
    delta = export_count - csv_count

    flag =
      if abs(delta) > max(5, div(max(csv_count, 1), 20)), do: " !!", else: ""

    IO.puts(
      "#{label}: export=#{export_count}  csv=#{csv_count}  delta=#{delta}#{flag}"
    )
  end

  defp read_json(path) do
    if File.exists?(path) do
      path |> File.read!() |> Jason.decode!()
    else
      []
    end
  end

  defp read_csv(path) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&strip_bom/1)
      |> CSV.decode!(headers: true)
      |> Enum.to_list()
    else
      Ysc.Logging.warning("[WP Reconcile] Missing CSV: #{path}")
      []
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(line), do: line

  defp normalize_email(email) when is_binary(email) do
    email = String.trim(email)

    if email == "" do
      nil
    else
      Email.normalize(email)
    end
  end

  defp normalize_email(_), do: nil
end
