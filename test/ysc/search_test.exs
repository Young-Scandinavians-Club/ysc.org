defmodule Ysc.SearchTest do
  @moduledoc """
  Tests for the Ysc.Search context module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Search
  alias Ysc.Events
  alias Ysc.EventsFixtures
  alias Ysc.Posts
  alias Ysc.Bookings.Booking
  alias Ysc.Repo

  setup do
    user =
      user_fixture(%{
        role: "admin",
        first_name: "SearchTest",
        last_name: "User"
      })

    organizer = user_fixture()

    {:ok, event} =
      Events.create_event(%{
        title: "Searchable Event Title",
        description: "An event for testing search",
        state: "published",
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, post} =
      Posts.create_post(
        %{
          "title" => "Searchable Post Title",
          "preview_text" => "Preview text for search",
          "body" => "Post body",
          "url_name" => "searchable-post",
          "state" => "published"
        },
        user
      )

    # Create a booking
    checkin_date = Date.add(Date.utc_today(), 7)
    checkout_date = Date.add(checkin_date, 2)

    booking =
      %Booking{
        user_id: user.id,
        property: :tahoe,
        booking_mode: :buyout,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        guests_count: 2,
        status: :complete,
        total_price: Money.new(500, :USD),
        reference_id: "BKG-SEARCH-#{System.unique_integer([:positive])}"
      }
      |> Repo.insert!()

    tier = EventsFixtures.ticket_tier_fixture(%{event_id: event.id})
    order = ticket_order_fixture(%{user: user, event: event, tier: tier})
    order = Repo.preload(order, :tickets)
    ticket = List.first(order.tickets)

    ticket =
      ticket
      |> Ecto.Changeset.change(
        reference_id: "TKT-SEARCH-#{System.unique_integer([:positive])}"
      )
      |> Repo.update!()

    %{user: user, event: event, post: post, booking: booking, ticket: ticket}
  end

  describe "global_search/2" do
    test "returns empty results for empty search term" do
      result = Search.global_search("")
      assert result.events == []
      assert result.posts == []
      assert result.tickets == []
      assert result.users == []
      assert result.bookings == []
    end

    test "returns empty results for nil search term" do
      result = Search.global_search(nil)
      assert result.events == []
      assert result.posts == []
      assert result.tickets == []
      assert result.users == []
      assert result.bookings == []
    end

    test "finds events by title", %{event: event} do
      result = Search.global_search("Searchable Event")
      assert result.events != []
      assert Enum.any?(result.events, fn e -> e.id == event.id end)
    end

    test "finds posts by title", %{post: post} do
      result = Search.global_search("Searchable Post")
      assert result.posts != []
      assert Enum.any?(result.posts, fn p -> p.id == post.id end)
    end

    test "finds users by name", %{user: user} do
      result = Search.global_search("SearchTest")
      assert result.users != []
      assert Enum.any?(result.users, fn u -> u.id == user.id end)
    end

    test "finds bookings by reference_id", %{booking: booking} do
      result = Search.global_search(booking.reference_id)
      assert result.bookings != []
      assert Enum.any?(result.bookings, fn b -> b.id == booking.id end)
    end

    test "respects limit parameter" do
      result = Search.global_search("test", 1)
      # Each category should have at most 1 result
      assert length(result.events) <= 1
      assert length(result.posts) <= 1
      assert length(result.users) <= 1
      assert length(result.bookings) <= 1
    end

    test "returns all categories in result" do
      result = Search.global_search("xyz")
      assert Map.has_key?(result, :events)
      assert Map.has_key?(result, :posts)
      assert Map.has_key?(result, :tickets)
      assert Map.has_key?(result, :users)
      assert Map.has_key?(result, :bookings)
    end

    test "does not match user email substrings in magic search" do
      _user =
        user_fixture(%{
          email: "magic.search.harvest@gmail.com",
          first_name: "Magic",
          last_name: "Harvest",
          state: :active
        })

      result = Search.global_search("@gmail.com")
      assert result.users == []
      assert result.tickets == []
      assert result.bookings == []
    end

    test "finds users, tickets, and bookings by full email address", %{
      user: user,
      ticket: ticket
    } do
      result = Search.global_search(user.email)

      assert Enum.any?(result.users, &(&1.id == user.id))
      assert Enum.any?(result.tickets, &(&1.id == ticket.id))
      assert Enum.any?(result.bookings, &(&1.user_id == user.id))
    end

    test "finds tickets by TKT- reference prefix", %{ticket: ticket} do
      result = Search.global_search(ticket.reference_id)

      assert Enum.any?(result.tickets, &(&1.id == ticket.id))
    end

    test "finds bookings by BKG- reference prefix", %{booking: booking} do
      result = Search.global_search(booking.reference_id)

      assert Enum.any?(result.bookings, &(&1.id == booking.id))
    end

    test "returns empty ticket and booking results for short queries" do
      result = Search.global_search("ab")

      assert result.tickets == []
      assert result.bookings == []
      assert result.users == []
    end
  end
end
