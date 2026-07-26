defmodule Ysc.WpMigration.ReconcileCsvsTest do
  use ExUnit.Case, async: true

  alias Ysc.WpMigration.ReconcileCsvs

  setup do
    tmp =
      System.tmp_dir!()
      |> Path.join("wp-reconcile-#{System.unique_integer([:positive])}")

    export_dir = Path.join(tmp, "export")
    csv_dir = Path.join(tmp, "csvs")
    File.mkdir_p!(export_dir)
    File.mkdir_p!(csv_dir)

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, export_dir: export_dir, csv_dir: csv_dir}
  end

  test "compares export users/memberships/subscriptions/bookings to CSVs", %{
    export_dir: export_dir,
    csv_dir: csv_dir
  } do
    File.write!(
      Path.join(export_dir, "users.json"),
      Jason.encode!([
        %{
          "email" => "a@example.com",
          "wcm_status" => "wcm-active",
          "sub_status" => "wc-active",
          "has_active_wp_subscription" => true
        },
        %{
          "email" => "b@example.com",
          "wcm_status" => "wcm-expired",
          "sub_status" => nil,
          "has_active_wp_subscription" => false
        }
      ])
    )

    File.write!(
      Path.join(export_dir, "bookings.json"),
      Jason.encode!([%{"id" => 1}])
    )

    File.write!(
      Path.join(csv_dir, "users.csv"),
      "Username,Name,Email\na,A,a@example.com\nb,B,b@example.com\n"
    )

    File.write!(
      Path.join(csv_dir, "memberships.csv"),
      "user_membership_id,membership_status\n1,active\n2,expired\n"
    )

    File.write!(
      Path.join(csv_dir, "subscriptions.csv"),
      "Status,Subscription,User ID,Auto Renewal\nactive,1,1,\n"
    )

    File.write!(
      Path.join(csv_dir, "bookings.csv"),
      "ID,Status\n1,Confirmed\n"
    )

    assert {:ok, report} =
             ReconcileCsvs.run(
               export_dir: export_dir,
               csv_dir: csv_dir,
               print: false
             )

    assert report.users.export == 2
    assert report.users.csv == 2
    assert report.active_memberships.export == 1
    assert report.active_memberships.csv == 1
    assert report.active_subscriptions.export == 1
    assert report.active_subscriptions.csv == 1
    assert report.active_subscriptions.on_hold_export == 0
    assert report.bookings.export == 1
    assert report.bookings.csv == 1
    assert report.bookings.csv_confirmed == 1
  end
end
