defmodule YscWeb.Workers.UserExporterTest do
  @moduledoc """
  Tests for UserExporter worker module.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.TestDataFactory, only: [user_with_membership: 1]

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

  defp require_csv_row!(rows, user_id) do
    case Enum.find(rows, &(&1["id"] == user_id)) do
      nil -> flunk("expected CSV row for user id #{user_id}")
      row -> row
    end
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
    filename =
      relative_path
      |> String.replace_prefix("/admin/exports/", "")
      |> Path.basename()

    full_path = Path.join([:code.priv_dir(:ysc), "static", "exports", filename])

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
      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)

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
      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)

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
      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)

      assert Map.get(row, "membership_renewal_date") == @expected_renewal_date
      assert Map.get(row, "membership_renewal_time") == @expected_renewal_time
      assert Map.get(row, "membership_renewal_tz") == @expected_renewal_tz
    end

    test "renewal columns are empty for users without a subscription", %{
      channel: channel
    } do
      user = user_fixture()

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)

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
      row = require_csv_row!(rows, user.id)

      assert Map.get(row, "membership_renewal_date") == "Never"
      assert Map.get(row, "membership_renewal_time") in [nil, ""]
      assert Map.get(row, "membership_renewal_tz") in [nil, ""]
    end
  end

  describe "only_subscribed filter" do
    test "includes sub-account when primary has lifetime membership (only_subscribed)",
         %{
           channel: channel
         } do
      primary = user_with_membership(:lifetime)

      sub =
        user_fixture()
        |> Ecto.Changeset.change(primary_user_id: primary.id)
        |> Repo.update!()

      path = run_export(channel, oban_job(channel, ["id", "email"], true))
      rows = parse_csv(path)
      exported_ids = Enum.map(rows, & &1["id"])

      assert primary.id in exported_ids
      assert sub.id in exported_ids
    end

    test "includes user with trialing subscription when only_subscribed is true",
         %{
           channel: channel
         } do
      user = user_fixture()

      {:ok, _} =
        Subscriptions.create_subscription(%{
          name: "Test Subscription",
          stripe_id: "sub_trialing_#{System.unique_integer([:positive])}",
          stripe_status: "trialing",
          user_id: user.id,
          current_period_end: @renewal_utc
        })

      path = run_export(channel, oban_job(channel, ["id", "email"], true))
      rows = parse_csv(path)

      assert Enum.any?(rows, &(&1["id"] == user.id))
    end

    test "includes user with past_due subscription when only_subscribed is true",
         %{
           channel: channel
         } do
      user = user_fixture()

      {:ok, _} =
        Subscriptions.create_subscription(%{
          name: "Test Subscription",
          stripe_id: "sub_past_due_#{System.unique_integer([:positive])}",
          stripe_status: "past_due",
          user_id: user.id,
          current_period_end: @renewal_utc
        })

      path = run_export(channel, oban_job(channel, ["id", "email"], true))
      rows = parse_csv(path)

      assert Enum.any?(rows, &(&1["id"] == user.id))
    end

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

    test "includes lifetime member without Stripe subscription when only_subscribed is true",
         %{
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

      path = run_export(channel, oban_job(channel, ["id", "email"], true))
      rows = parse_csv(path)

      assert Enum.any?(rows, &(&1["id"] == user.id))
    end
  end

  describe "sub-accounts and inheritance columns" do
    test "marks membership inherited and primary user fields for sub-account under lifetime primary",
         %{
           channel: channel
         } do
      primary = user_with_membership(:lifetime)

      sub =
        user_fixture()
        |> Ecto.Changeset.change(primary_user_id: primary.id)
        |> Repo.update!()

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      rows = parse_csv(path)
      row = require_csv_row!(rows, sub.id)

      assert row["membership_inherited"] == "Yes"
      assert row["primary_user_email"] == primary.email
      assert row["primary_user_id"] == to_string(primary.id)
    end
  end

  describe "export progress" do
    test "broadcasts user_export:progress before user_export:complete", %{
      channel: channel
    } do
      _user = user_fixture()

      YscWeb.Endpoint.subscribe(channel)

      job = oban_job(channel, ["id"], false)

      assert :ok = UserExporter.perform(job)

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_export:progress",
                       payload: percent
                     },
                     15_000

      assert percent in 0..100

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_export:complete",
                       payload: _path
                     },
                     15_000
    end
  end

  describe "selected fields" do
    test "only exports requested fields plus the fixed membership columns", %{
      channel: channel
    } do
      user = user_fixture()

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)

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
      row = require_csv_row!(rows, user.id)

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
      row = require_csv_row!(rows, user.id)

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
      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)

      refute Map.has_key?(row, "address")
      refute Map.has_key?(row, "city")
      refute Map.has_key?(row, "region")
      refute Map.has_key?(row, "postal_code")
      refute Map.has_key?(row, "country")
    end
  end

  describe "field names and membership label edge cases" do
    test "accepts field names as atoms (Admin-style args)", %{channel: channel} do
      user = user_fixture()

      path =
        run_export(
          channel,
          oban_job(channel, [:id, :email], false)
        )

      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)
      assert row["id"]
      assert row["email"]
    end

    test "membership_type uses configured plan name when stripe_price_id matches Single plan",
         %{channel: channel} do
      user = user_fixture()

      single =
        Enum.find(
          Application.fetch_env!(:ysc, :membership_plans),
          &(&1.id == :single)
        )

      {:ok, sub} =
        Subscriptions.create_subscription(%{
          name: "Test Subscription",
          stripe_id: "sub_single_named_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          user_id: user.id,
          current_period_end: @renewal_utc
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          stripe_id: "si_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_single_test",
          stripe_price_id: single.stripe_price_id,
          quantity: 1,
          subscription_id: sub.id
        })

      path = run_export(channel, oban_job(channel, ["id"], false))
      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)

      assert row["membership_type"] == "Single"
    end

    test "accepts field names as strings (to_existing_atom)", %{
      channel: channel
    } do
      user = user_fixture()

      path =
        run_export(
          channel,
          oban_job(channel, ["id", "email"], false)
          |> then(fn job ->
            %{job | args: Map.put(job.args, "fields", ["id", "email"])}
          end)
        )

      rows = parse_csv(path)
      row = require_csv_row!(rows, user.id)
      assert row["id"]
      assert row["email"]
    end

    test "membership type is empty when stripe price id does not match any membership plan",
         %{channel: channel} do
      user = user_fixture()

      {:ok, sub} =
        Subscriptions.create_subscription(%{
          name: "Test",
          stripe_id: "sub_unknown_plan_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          user_id: user.id,
          current_period_end: @renewal_utc
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          stripe_id: "si_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_x",
          stripe_price_id:
            "price_not_in_config_#{System.unique_integer([:positive])}",
          quantity: 1,
          subscription_id: sub.id
        })

      plans = Application.get_env(:ysc, :membership_plans)

      try do
        Application.put_env(:ysc, :membership_plans, [
          %{id: :other_plan, name: "Other", stripe_price_id: "price_unused"}
        ])

        path = run_export(channel, oban_job(channel, ["id"], false))
        rows = parse_csv(path)
        row = require_csv_row!(rows, user.id)

        assert row["membership_type"] in [nil, ""]
      after
        Application.put_env(:ysc, :membership_plans, plans)
      end
    end

    test "membership_type is Unknown when plan matches id but entry has no name field",
         %{channel: channel} do
      user = user_fixture()

      single =
        Enum.find(
          Application.fetch_env!(:ysc, :membership_plans),
          &(&1.id == :single)
        )

      {:ok, sub} =
        Subscriptions.create_subscription(%{
          name: "Test Subscription",
          stripe_id: "sub_unknown_name_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          user_id: user.id,
          current_period_end: @renewal_utc
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          stripe_id: "si_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_single_test",
          stripe_price_id: single.stripe_price_id,
          quantity: 1,
          subscription_id: sub.id
        })

      plans = Application.get_env(:ysc, :membership_plans)

      try do
        # Plan map matches Enum.find on id but does not match %{name: name} in case
        Application.put_env(:ysc, :membership_plans, [
          Map.drop(single, [:name])
        ])

        path = run_export(channel, oban_job(channel, ["id"], false))
        rows = parse_csv(path)
        row = require_csv_row!(rows, user.id)

        assert row["membership_type"] == "Unknown"
      after
        Application.put_env(:ysc, :membership_plans, plans)
      end
    end

    test "sub-account whose primary has no membership shows inherited No and primary email",
         %{channel: channel} do
      primary = user_fixture()

      sub =
        user_fixture()
        |> Ecto.Changeset.change(primary_user_id: primary.id)
        |> Repo.update!()

      path = run_export(channel, oban_job(channel, ["id", "email"], false))
      rows = parse_csv(path)
      row = require_csv_row!(rows, sub.id)

      assert row["membership_inherited"] == "No"
      assert row["primary_user_email"] == primary.email
      assert row["primary_user_id"] == to_string(primary.id)
    end
  end
end
