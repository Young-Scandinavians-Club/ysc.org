defmodule YscWeb.AdminSearchComponentTest do
  @moduledoc """
  Fail-closed defaults for the admin magic-search box.

  The dashboard always passes `admin_role`, but if a caller omits it the
  component must search as a volunteer (no users or cabin bookings).
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias YscWeb.AdminSearchComponent

  defp new_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)
    }
  end

  test "mount defaults a missing admin_role to volunteer" do
    {:ok, socket} = AdminSearchComponent.mount(new_socket())
    assert socket.assigns.admin_role == :volunteer
  end

  test "search without an assigned admin_role omits users and bookings" do
    unique = "FailClosed#{System.unique_integer([:positive])}"

    member =
      user_fixture(%{
        first_name: unique,
        last_name: "Member",
        email: "#{String.downcase(unique)}@ysc.org"
      })

    booking =
      booking_fixture(%{
        user_id: member.id,
        status: :complete,
        reference_id: "BK-#{unique}"
      })

    {:ok, socket} = AdminSearchComponent.mount(new_socket())

    {:noreply, volunteer_socket} =
      AdminSearchComponent.handle_event(
        "search",
        %{"query" => unique},
        socket
      )

    assert volunteer_socket.assigns.admin_role == :volunteer
    assert volunteer_socket.assigns.results.users == []
    assert volunteer_socket.assigns.results.bookings == []

    refute Enum.any?(
             volunteer_socket.assigns.results.users,
             &(&1.id == member.id)
           )

    {:ok, admin_socket} =
      AdminSearchComponent.mount(new_socket(%{admin_role: :admin}))

    {:noreply, admin_socket} =
      AdminSearchComponent.handle_event(
        "search",
        %{"query" => unique},
        admin_socket
      )

    assert Enum.any?(admin_socket.assigns.results.users, &(&1.id == member.id))

    {:noreply, admin_booking_socket} =
      AdminSearchComponent.handle_event(
        "search",
        %{"query" => booking.reference_id},
        admin_socket
      )

    assert Enum.any?(
             admin_booking_socket.assigns.results.bookings,
             &(&1.id == booking.id)
           )
  end

  test "placeholder does not prompt a missing role to search users or bookings" do
    html = render_component(AdminSearchComponent, %{id: "unscoped"})
    doc = LazyHTML.from_document(html)
    input = LazyHTML.query(doc, "input[type=search]")

    assert LazyHTML.attribute(input, "placeholder") == [
             "Search events, posts, tickets..."
           ]
  end
end
