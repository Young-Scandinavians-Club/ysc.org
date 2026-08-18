defmodule YscWeb.Api.PropertiesControllerTest do
  @moduledoc """
  Tests for the mobile API properties info endpoint.

  Covers static property info, settings overrides, tab structure,
  markdown content, validation, and authentication.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Bookings
  alias Ysc.Bookings.DoorCode
  alias Ysc.Repo
  alias Ysc.Settings
  alias Ysc.SiteSettings.SiteSetting
  alias Ysc.Test.KioskAPIKeyHelper

  @test_token "test-kiosk-secret"
  @expected_tab_ids ~w(welcome etiquette bears parking checkout emergency)
  @expected_clear_lake_tab_ids ~w(welcome etiquette water parking cleaning checkout emergency)

  setup %{conn: conn} do
    original = KioskAPIKeyHelper.capture_kiosk_api_key!(@test_token)
    Settings.clear_cache()

    on_exit(fn ->
      KioskAPIKeyHelper.restore_kiosk_api_key!(original)
    end)

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{@test_token}")

    {:ok, conn: authed_conn}
  end

  describe "GET /api/v1/mobile/properties/:property/info" do
    test "returns property info for tahoe", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["property"] == "tahoe"
      assert data["name"] == "Lake Tahoe Cabin"
    end

    test "returns property info for clear_lake", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["property"] == "clear_lake"
      assert data["name"] == "Clear Lake Cabin"
    end

    test "response includes all required top-level fields", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert Map.has_key?(data, "property")
      assert Map.has_key?(data, "name")
      assert Map.has_key?(data, "content_format")
      assert data["content_format"] == "markdown"
      assert Map.has_key?(data, "check_in_time")
      assert Map.has_key?(data, "check_out_time")
      assert Map.has_key?(data, "check_in_instructions")
      assert Map.has_key?(data, "check_out_instructions")
      assert Map.has_key?(data, "notices")
      assert Map.has_key?(data, "wifi_network")
      assert Map.has_key?(data, "wifi_password")
      assert Map.has_key?(data, "door_code")
      assert Map.has_key?(data, "rooms")
      assert Map.has_key?(data, "tabs")
      assert Map.has_key?(data, "additional_settings")
    end

    test "rooms is an array of objects with id and name", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert is_list(data["rooms"])

      for room <- data["rooms"] do
        assert Map.has_key?(room, "id")
        assert Map.has_key?(room, "name")
        assert is_binary(room["id"])
        assert is_binary(room["name"])
      end
    end

    test "tahoe response includes rooms when rooms exist", %{conn: conn} do
      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Test Category #{System.unique_integer()}"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Test Room #{System.unique_integer()}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      room_ids = Enum.map(data["rooms"], & &1["id"])
      assert to_string(room.id) in room_ids
    end

    test "tahoe uses static check-in and check-out times when no overrides", %{
      conn: conn
    } do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["check_in_time"] == "3:00 PM"
      assert data["check_out_time"] == "11:00 AM"
    end

    test "clear_lake uses static check-in and check-out times", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["check_in_time"] == "3:00 PM"
      assert data["check_out_time"] == "11:00 AM"
    end

    test "tahoe returns tabs in correct order with all categories", %{
      conn: conn
    } do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      tab_ids = Enum.map(tabs, & &1["id"])
      assert tab_ids == @expected_tab_ids
    end

    test "each tab has id, title, and sections", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)

      for tab <- tabs do
        assert Map.has_key?(tab, "id")
        assert Map.has_key?(tab, "title")
        assert Map.has_key?(tab, "sections")
        assert is_list(tab["sections"])
      end
    end

    test "each tab has at least one section", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)

      for tab <- tabs do
        refute Enum.empty?(tab["sections"]),
               "Tab #{tab["id"]} should have at least one section"
      end
    end

    test "each section has title and content", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)

      for tab <- tabs do
        for section <- tab["sections"] do
          assert Map.has_key?(section, "title")
          assert Map.has_key?(section, "content")
          assert is_binary(section["title"])
          assert is_binary(section["content"])
        end
      end
    end

    test "welcome tab has expected sections", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      welcome_tab = Enum.find(tabs, &(&1["id"] == "welcome"))

      section_titles = Enum.map(welcome_tab["sections"], & &1["title"])
      assert "The YSC Spirit" in section_titles
      assert "The Must-Bring List" in section_titles
    end

    test "etiquette tab covers quiet hours and pets", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      etiquette_tab = Enum.find(tabs, &(&1["id"] == "etiquette"))

      sections_text =
        etiquette_tab["sections"] |> Enum.map_join(" ", & &1["content"])

      assert sections_text =~ "10:00 PM"
      assert sections_text =~ "Pets"
    end

    test "parking tab has expected sections", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      parking_tab = Enum.find(tabs, &(&1["id"] == "parking"))

      section_titles = Enum.map(parking_tab["sections"], & &1["title"])
      assert "Parking" in section_titles
      assert "Winter Driving" in section_titles
    end

    test "clear_lake water tab covers dock access and mussel inspection", %{
      conn: conn
    } do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      water_tab = Enum.find(tabs, &(&1["id"] == "water"))

      sections_text =
        water_tab["sections"] |> Enum.map_join(" ", & &1["content"])

      assert sections_text =~ "mooring"
      assert sections_text =~ "Quagga"
    end

    test "clear_lake etiquette tab covers quiet hours", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      etiquette_tab = Enum.find(tabs, &(&1["id"] == "etiquette"))

      sections_text =
        etiquette_tab["sections"] |> Enum.map_join(" ", & &1["content"])

      assert sections_text =~ "midnight"
    end

    test "clear_lake welcome and cleaning tabs describe seasonal sleeping", %{
      conn: conn
    } do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)

      welcome_tab = Enum.find(tabs, &(&1["id"] == "welcome"))
      cleaning_tab = Enum.find(tabs, &(&1["id"] == "cleaning"))

      welcome_text =
        welcome_tab["sections"] |> Enum.map_join(" ", & &1["content"])

      cleaning_titles = Enum.map(cleaning_tab["sections"], & &1["title"])

      cleaning_text =
        cleaning_tab["sections"] |> Enum.map_join(" ", & &1["content"])

      assert welcome_text =~ "May 1 – Oct 31"
      assert welcome_text =~ "Nov 1 – Apr 30"
      assert welcome_text =~ "lawn camp"
      assert welcome_text =~ "beds are not set up"
      assert welcome_text =~ "three rooms"
      assert welcome_text =~ "queen"
      assert welcome_text =~ "full-size"
      assert "Winter Season (Nov 1 – Apr 30)" in cleaning_titles
      assert cleaning_text =~ "three separate rooms"
      assert cleaning_text =~ "bedside tables, lamps, heaters"
      refute cleaning_text =~ "Oct–April"
    end

    test "clear_lake returns tabs in correct order", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      tab_ids = Enum.map(tabs, & &1["id"])
      assert tab_ids == @expected_clear_lake_tab_ids
    end

    test "content includes markdown formatting", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      welcome_tab = Enum.find(tabs, &(&1["id"] == "welcome"))
      first_section = hd(welcome_tab["sections"])

      assert first_section["content"] =~ "**"
    end

    test "bears tab Bear Safety has numbered list", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      bears_tab = Enum.find(tabs, &(&1["id"] == "bears"))

      bear_section =
        Enum.find(
          bears_tab["sections"],
          &(&1["title"] == "Bear Safety & Electric Wire")
        )

      assert bear_section["content"] =~ "1."
      assert bear_section["content"] =~ "2."
    end

    test "checkout Dugnad checklist has bullet list", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => %{"tabs" => tabs}} = json_response(response, 200)
      checkout_tab = Enum.find(tabs, &(&1["id"] == "checkout"))

      checklist_section =
        Enum.find(
          checkout_tab["sections"],
          &(&1["title"] == "The Dugnad Cleaning Checklist")
        )

      assert checklist_section["content"] =~ "-"
    end

    test "tahoe_check_in_time from settings overrides static default", %{
      conn: conn
    } do
      %SiteSetting{
        name: "tahoe_check_in_time",
        value: "4:00 PM",
        group: "tahoe"
      }
      |> Repo.insert!()

      Settings.clear_cache()

      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["check_in_time"] == "4:00 PM"
    end

    test "tahoe_check_out_time from settings overrides static default", %{
      conn: conn
    } do
      %SiteSetting{
        name: "tahoe_check_out_time",
        value: "10:00 AM",
        group: "tahoe"
      }
      |> Repo.insert!()

      Settings.clear_cache()

      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["check_out_time"] == "10:00 AM"
    end

    test "additional_settings contains property-prefixed settings", %{
      conn: conn
    } do
      %SiteSetting{name: "tahoe_door_code", value: "1234", group: "tahoe"}
      |> Repo.insert!()

      Settings.clear_cache()

      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["additional_settings"]["door_code"] == "1234"
    end

    test "top-level door_code uses active door code when present", %{
      conn: conn
    } do
      %SiteSetting{name: "tahoe_door_code", value: "1234", group: "tahoe"}
      |> Repo.insert!()

      {:ok, _door_code} =
        %DoorCode{}
        |> DoorCode.changeset(%{
          code: "ACT1",
          property: :tahoe,
          active_from: DateTime.utc_now()
        })
        |> Repo.insert()

      Settings.clear_cache()

      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["door_code"] == "ACT1"
    end

    test "top-level door_code falls back to settings when no active door code",
         %{
           conn: conn
         } do
      %SiteSetting{name: "tahoe_door_code", value: "5678", group: "tahoe"}
      |> Repo.insert!()

      Settings.clear_cache()

      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["door_code"] == "5678"
    end

    test "check_in_instructions from settings appears in response", %{
      conn: conn
    } do
      %SiteSetting{
        name: "tahoe_check_in_instructions",
        value: "Use the keypad. Code is 5678.",
        group: "tahoe"
      }
      |> Repo.insert!()

      Settings.clear_cache()

      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["check_in_instructions"] == "Use the keypad. Code is 5678."
    end

    test "returns 400 for invalid property", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/invalid/info")

      assert json_response(response, 400) == %{
               "error" => "invalid property. Use 'tahoe' or 'clear_lake'"
             }
    end

    test "returns 400 for empty property path segment", %{conn: conn} do
      response = get(conn, "/api/v1/mobile/properties//info")

      assert response.status in [400, 404]
    end

    test "returns 401 without authorization header", %{conn: conn} do
      unauthed_conn = delete_req_header(conn, "authorization")
      response = get(unauthed_conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert json_response(response, 401)
    end

    test "returns 401 with invalid token", %{conn: conn} do
      bad_conn =
        conn
        |> delete_req_header("authorization")
        |> put_req_header("authorization", "Bearer wrong-token")

      response = get(bad_conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert json_response(response, 401)
    end

    test "includes cabin master details in emergency tab when board member exists",
         %{
           conn: conn
         } do
      user_fixture(%{first_name: "Casey", last_name: "Master"})
      |> Ecto.Changeset.change(
        board_position: :clear_lake_cabin_master,
        phone_number: "+14155551234"
      )
      |> Repo.update!()

      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => data} = json_response(response, 200)
      assert %{"tabs" => tabs} = data
      emergency = Enum.find(tabs, &(&1["id"] == "emergency"))
      assert emergency

      sections_text =
        emergency["sections"] |> Enum.map_join(" ", & &1["content"])

      assert sections_text =~ "Casey"
      assert sections_text =~ "Master"
    end
  end
end
