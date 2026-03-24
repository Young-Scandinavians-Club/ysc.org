defmodule YscWeb.Workers.UserExporterTest do
  @moduledoc """
  Tests for UserExporter worker module.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias YscWeb.Workers.UserExporter
  alias Ysc.Subscriptions
  alias Ysc.Accounts
  alias Ysc.Repo

  # A fixed future datetime in January (PST = UTC-8, no DST ambiguity).
  # 2030-01-15 20:30:00 UTC → 2030-01-15 12:30:00 PST
  @renewal_utc ~U[2030-01-15 20:30:00Z]
  @expected_renewal_date "2030-01-15"
  @expected_renewal_time "12:30 PM"
  @expected_renewal_tz "PST"

  defp oban_job(channel, fields, only_subscribed) do
    %Oban.Job{
      id: System.unique_integer([:positive]),
      args: %{
        "channel" => channel,
        "fields" => fields,
        "only_subscribed" => only_subscribed
      },
      worker: "YscWeb.Workers.UserExporter",
      queue: "exports",
      state: "available",
      attempt: 1
    }
  end

  defp run_export(channel, job) do
    YscWeb.Endpoint.subscribe(channel)
    :ok = UserExporter.perform(job)

    receive do
      %Phoenix.Socket.Broadcast{event: "user_export:complete", payload: path} ->
        path

      %Phoenix.Socket.Broadcast{event: "user_export:failed", payload: msg} ->
        flunk("Export failed: #{inspect(msg)}")
    after
      15_000 ->
        flunk("No export:complete broadcast received within 15s")
    end
  end

  defp parse_csv(relative_path) do
    full_path = "#{:code.priv_dir(:ysc)}/static#{relative_path}"

    on_exit(fn -> File.rm(full_path) end)

    full_path
    |> File.stream!()
    |> CSV.decode(headers: true)
    |> Enum.map(fn {:ok, row} -> row end)
  end

  defp create_active_subscription(user, current_period_end) do
    {:ok, sub} =
      Subscriptions.create_subscription(%{
        name: "Test Subscription",
        stripe_id: "sub_test_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        user_id: user.id,
        current_period_end: current_period_end
      })

    sub
  end

  setup do
    %{channel: "exporter:test_#{System.unique_integer([:positive])}"}
  end

  describe "CSV columns" do
    test "includes membership_renewal_date, _time, and _tz as separate columns",
         %{
           channel: channel
         } do
      user = user_fixture()
      create_active_subscription(user, @renewal_utc)

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      [row | _] = parse_csv(path)

      assert Map.has_key?(row, "membership_renewal_date")
      assert Map.has_key?(row, "membership_renewal_time")
      assert Map.has_key?(row, "membership_renewal_tz")
    end

    test "does not include the old combined membership_renewal_date column with datetime",
         %{
           channel: channel
         } do
      user = user_fixture()
      create_active_subscription(user, @renewal_utc)

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      [row | _] = parse_csv(path)

      # The date column should be just a date string, not a combined datetime+tz string
      date_val = Map.get(row, "membership_renewal_date")
      refute String.contains?(date_val || "", " ")
    end
  end

  describe "renewal date values" do
    test "splits renewal datetime into correct date, time, and tz for active subscription",
         %{
           channel: channel
         } do
      user = user_fixture()
      create_active_subscription(user, @renewal_utc)

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      [row | _] = parse_csv(path)

      assert Map.get(row, "membership_renewal_date") == @expected_renewal_date
      assert Map.get(row, "membership_renewal_time") == @expected_renewal_time
      assert Map.get(row, "membership_renewal_tz") == @expected_renewal_tz
    end

    test "renewal columns are empty for users without a subscription", %{
      channel: channel
    } do
      _user = user_fixture()

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      [row | _] = parse_csv(path)

      assert Map.get(row, "membership_renewal_date") in [nil, ""]
      assert Map.get(row, "membership_renewal_time") in [nil, ""]
      assert Map.get(row, "membership_renewal_tz") in [nil, ""]
    end

    test "lifetime membership shows 'Never' for date and empty time/tz", %{
      channel: channel
    } do
      user = user_fixture()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update()

      path = run_export(channel, oban_job(channel, ["id", "email"], false))

      rows = parse_csv(path)
      row = Enum.find(rows, &(&1["id"] == user.id))

      assert Map.get(row, "membership_renewal_date") == "Never"
      assert Map.get(row, "membership_renewal_time") in [nil, ""]
      assert Map.get(row, "membership_renewal_tz") in [nil, ""]
    end
  end

  describe "only_subscribed filter" do
    test "excludes users without active subscriptions when only_subscribed is true",
         %{
           channel: channel
         } do
      subscribed_user = user_fixture()
      create_active_subscription(subscribed_user, @renewal_utc)
      unsubscribed_user = user_fixture()

      path = run_export(channel, oban_job(channel, ["id", "email"], true))
      rows = parse_csv(path)
      exported_ids = Enum.map(rows, & &1["id"])

      assert subscribed_user.id in exported_ids
      refute unsubscribed_user.id in exported_ids
    end
  end

  describe "selected fields" do
    test "only exports requested fields plus the fixed membership columns", %{
      channel: channel
    } do
      _user = user_fixture()

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      [row | _] = parse_csv(path)

      assert Map.has_key?(row, "id")
      assert Map.has_key?(row, "email")
      assert Map.has_key?(row, "membership_type")
      assert Map.has_key?(row, "membership_renewal_date")
      assert Map.has_key?(row, "membership_renewal_time")
      assert Map.has_key?(row, "membership_renewal_tz")
      assert Map.has_key?(row, "membership_inherited")
      assert Map.has_key?(row, "primary_user_email")
      assert Map.has_key?(row, "primary_user_id")
      refute Map.has_key?(row, "first_name")
      refute Map.has_key?(row, "last_name")
    end
  end

  describe "address field" do
    test "expands address into five sub-columns when included", %{
      channel: channel
    } do
      user = user_fixture()

      {:ok, _} =
        Accounts.update_billing_address(user, %{
          "address" => "100 Fjord Lane",
          "city" => "Bergen",
          "region" => "CA",
          "postal_code" => "94102",
          "country" => "US"
        })

      path = run_export(channel, oban_job(channel, ["id", "address"], false))
      rows = parse_csv(path)
      row = Enum.find(rows, &(&1["id"] == user.id))

      assert Map.has_key?(row, "address")
      assert Map.has_key?(row, "city")
      assert Map.has_key?(row, "region")
      assert Map.has_key?(row, "postal_code")
      assert Map.has_key?(row, "country")
      assert row["address"] == "100 Fjord Lane"
      assert row["city"] == "Bergen"
      assert row["region"] == "CA"
      assert row["postal_code"] == "94102"
      assert row["country"] == "US"
    end

    test "address sub-columns are empty when user has no billing address", %{
      channel: channel
    } do
      user = user_fixture()

      path = run_export(channel, oban_job(channel, ["id", "address"], false))
      rows = parse_csv(path)
      row = Enum.find(rows, &(&1["id"] == user.id))

      assert row["address"] in [nil, ""]
      assert row["city"] in [nil, ""]
      assert row["region"] in [nil, ""]
      assert row["postal_code"] in [nil, ""]
      assert row["country"] in [nil, ""]
    end

    test "address columns are absent when address field is not requested", %{
      channel: channel
    } do
      user = user_fixture()

      {:ok, _} =
        Accounts.update_billing_address(user, %{
          "address" => "1 Viking Ave",
          "city" => "Oslo",
          "region" => "NY",
          "postal_code" => "10001",
          "country" => "US"
        })

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      [row | _] = parse_csv(path)

      refute Map.has_key?(row, "address")
      refute Map.has_key?(row, "city")
      refute Map.has_key?(row, "region")
      refute Map.has_key?(row, "postal_code")
      refute Map.has_key?(row, "country")
    end
  end
end
