defmodule YscWeb.Components.MapComponentTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.Components.MapComponent

  describe "render/1" do
    test "renders map container with correct structure" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      assert html =~ "id=\"mapComponent\""
      assert html =~ "id=\"map\""
      assert html =~ "phx-hook=\"RadarMap\""
      assert html =~ "phx-update=\"ignore\""
    end

    test "applies correct styling classes" do
      assigns = %{
        id: "test-map",
        latitude: 37.7749,
        longitude: -122.4194,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      assert html =~ "border"
      assert html =~ "border-zinc-300"
      assert html =~ "rounded"
      assert html =~ "w-full"
      assert html =~ "h-80"
    end

    test "sets overflow hidden style" do
      assigns = %{
        id: "test-map",
        latitude: 40.7128,
        longitude: -74.0060,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      assert html =~ ~s(style="overflow: hidden")
    end

    test "uses phx-update ignore to prevent DOM updates" do
      assigns = %{
        id: "test-map",
        latitude: 51.5074,
        longitude: -0.1278,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      assert html =~ ~s(phx-update="ignore")
    end
  end

  describe "update/2" do
    test "assigns latitude and longitude from assigns" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == 38.9072
      assert socket.assigns.longitude == -77.0369
    end

    test "handles nil latitude and longitude" do
      assigns = %{
        id: "test-map",
        latitude: nil,
        longitude: nil,
        locked: false
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == nil
      assert socket.assigns.longitude == nil
    end

    test "handles locked parameter" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: true
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == 38.9072
      assert socket.assigns.longitude == -77.0369
    end

    test "handles unlocked parameter" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == 38.9072
      assert socket.assigns.longitude == -77.0369
    end
  end

  describe "coordinate handling" do
    test "works with positive coordinates" do
      assigns = %{
        id: "test-map",
        latitude: 45.5231,
        longitude: 122.6765,
        locked: false
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == 45.5231
      assert socket.assigns.longitude == 122.6765
    end

    test "works with negative coordinates" do
      assigns = %{
        id: "test-map",
        latitude: -33.8688,
        longitude: -151.2093,
        locked: false
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == -33.8688
      assert socket.assigns.longitude == -151.2093
    end

    test "works with zero coordinates" do
      assigns = %{
        id: "test-map",
        latitude: 0.0,
        longitude: 0.0,
        locked: false
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == 0.0
      assert socket.assigns.longitude == 0.0
    end

    test "works with decimal coordinates" do
      assigns = %{
        id: "test-map",
        latitude: 37.774929,
        longitude: -122.419418,
        locked: false
      }

      {:ok, socket} = MapComponent.update(assigns, %Phoenix.LiveView.Socket{})

      assert socket.assigns.latitude == 37.774929
      assert socket.assigns.longitude == -122.419418
    end
  end

  describe "map hook integration" do
    test "includes RadarMap hook" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      assert html =~ ~s(phx-hook="RadarMap")
    end

    test "provides map element with id for JavaScript hook" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      # Map div should have id="map" for the hook to find it
      assert html =~ ~s(id="map")
    end
  end

  describe "container structure" do
    test "has outer container with mapComponent id" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      assert html =~ ~s(id="mapComponent")
    end

    test "has inner map div for rendering" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      # Should have nested structure
      assert html =~ ~s(<div)
      assert html =~ ~s(id="map")
    end
  end

  describe "responsive design" do
    test "uses full width" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      assert html =~ "w-full"
    end

    test "uses fixed height" do
      assigns = %{
        id: "test-map",
        latitude: 38.9072,
        longitude: -77.0369,
        locked: false
      }

      html = render_component(MapComponent, assigns)

      # Both containers should have h-80
      assert html =~ "h-80"
    end
  end
end
