defmodule YscWeb.Emails.OutageNotificationTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Repo
  alias YscWeb.Emails.OutageNotification

  describe "get_template_name/0 and get_subject/0" do
    test "returns static identifiers" do
      assert OutageNotification.get_template_name() == "outage_notification"

      assert OutageNotification.get_subject() ==
               "Property Outage Alert - Young Scandinavians Club"
    end
  end

  describe "get_cabin_master/1 and get_cabin_master_email/1" do
    test "returns tahoe cabin master user when one is assigned" do
      master =
        user_fixture()
        |> Ecto.Changeset.change(%{board_position: :tahoe_cabin_master})
        |> Repo.update!()

      assert %Ysc.Accounts.User{id: id} =
               OutageNotification.get_cabin_master(:tahoe)

      assert id == master.id
    end

    test "resolves property from binary strings" do
      assert OutageNotification.get_cabin_master("tahoe") ==
               OutageNotification.get_cabin_master(:tahoe)

      assert OutageNotification.get_cabin_master_email("clear_lake") ==
               OutageNotification.get_cabin_master_email(:clear_lake)
    end

    test "returns nil for unknown property atoms and cabin master" do
      assert OutageNotification.get_cabin_master(:unknown) == nil
      assert OutageNotification.get_cabin_master_email(:unknown) == nil
    end

    test "returns nil for unknown property strings in rescue path" do
      assert OutageNotification.get_cabin_master("not_a_real_property_xyz") ==
               nil

      assert OutageNotification.get_cabin_master_email(
               "not_a_real_property_xyz"
             ) ==
               nil
    end
  end

  describe "format_date/1" do
    test "formats a Date struct with long month and day" do
      assert OutageNotification.format_date(~D[2024-06-15]) =~ "June"
      assert OutageNotification.format_date(~D[2024-06-15]) =~ "2024"
    end

    test "parses ISO8601 date strings" do
      assert OutageNotification.format_date("2024-12-01") =~ "December"
    end

    test "returns Unknown date when ISO date string is invalid" do
      assert OutageNotification.format_date("not-a-date") == "Unknown date"
    end

    test "returns Unknown date for unsupported values" do
      assert OutageNotification.format_date(123) == "Unknown date"
    end
  end

  describe "property_name/1" do
    test "maps known atoms and binaries" do
      assert OutageNotification.property_name(:tahoe) == "Tahoe Property"

      assert OutageNotification.property_name(:clear_lake) ==
               "Clear Lake Property"

      assert OutageNotification.property_name(:other) == "Property"
      assert OutageNotification.property_name("tahoe") == "Tahoe Property"

      assert OutageNotification.property_name("clear_lake") ==
               "Clear Lake Property"
    end
  end

  describe "incident_type_name/1" do
    test "maps known incident types" do
      assert OutageNotification.incident_type_name(:power_outage) ==
               "Power Outage"

      assert OutageNotification.incident_type_name(:water_outage) ==
               "Water Outage"

      assert OutageNotification.incident_type_name(:internet_outage) ==
               "Internet Outage"

      assert OutageNotification.incident_type_name(:other) == "Outage"

      assert OutageNotification.incident_type_name("power_outage") ==
               "Power Outage"

      assert OutageNotification.incident_type_name("unknown_type") == "Outage"
    end
  end

  describe "provider_outage_map_url/1" do
    test "returns vendor URLs and nil for unknown" do
      assert OutageNotification.provider_outage_map_url("Optimum") =~
               "optimum.com"

      assert OutageNotification.provider_outage_map_url("Liberty Utilities") =~
               "liberty"

      assert OutageNotification.provider_outage_map_url("PG&E") =~ "pge"
      assert OutageNotification.provider_outage_map_url("SCG") =~ "swgas"
      assert OutageNotification.provider_outage_map_url("Other Co") == nil
    end
  end

  describe "fallback clauses" do
    test "property_name and incident_type_name for non-atom non-binary values" do
      assert OutageNotification.property_name(123) == "Property"
      assert OutageNotification.incident_type_name(%{}) == "Outage"
    end

    test "format_date returns Unknown date for DateTime and other unsupported types" do
      assert OutageNotification.format_date(~U[2024-06-15 12:00:00Z]) ==
               "Unknown date"

      assert OutageNotification.format_date(:not_a_date) == "Unknown date"
    end
  end

  describe "render/1" do
    setup do
      %{user: user_fixture()}
    end

    test "includes description, cabin master contact block, and outage map button",
         %{user: user} do
      assigns = %{
        first_name: user.first_name,
        property: :clear_lake,
        incident_type: :water_outage,
        company_name: "PG&E",
        incident_date: "2024-11-20",
        description: "Planned maintenance in the area.",
        checkin_date: ~D[2024-11-22],
        checkout_date: ~D[2024-11-24],
        cabin_master_name: "Alex Nord",
        cabin_master_email: "alex@example.com",
        cabin_master_phone: "555-0100"
      }

      html = OutageNotification.render(assigns)
      assert html =~ "Planned maintenance"
      assert html =~ "Alex Nord"
      assert html =~ "alex@example.com"
      assert html =~ "555-0100"
      assert html =~ "pgealerts.alerts.pge.com"
    end

    test "omits description and cabin block when not provided", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        property: :tahoe,
        incident_type: :power_outage,
        company_name: "Unknown Utility",
        incident_date: ~D[2024-06-01],
        description: nil,
        checkin_date: ~D[2024-06-10],
        checkout_date: ~D[2024-06-12],
        cabin_master_name: nil,
        cabin_master_email: nil,
        cabin_master_phone: nil
      }

      html = OutageNotification.render(assigns)
      refute html =~ "Description:"
      refute html =~ "Cabin Master:"
      refute html =~ "View Outage Map"
    end

    test "shows cabin block when only email is set", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        property: :tahoe,
        incident_type: :internet_outage,
        company_name: "Other",
        incident_date: ~D[2024-01-01],
        description: nil,
        checkin_date: ~D[2024-01-05],
        checkout_date: ~D[2024-01-07],
        cabin_master_name: nil,
        cabin_master_email: "only@example.com",
        cabin_master_phone: nil
      }

      html = OutageNotification.render(assigns)
      assert html =~ "only@example.com"
      refute html =~ "Cabin Master:"
    end
  end
end
