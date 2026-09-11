defmodule Ysc.SearchTest do
  @moduledoc """
  Tests for the Ysc.Search context module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Search
  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Posts
  alias Ysc.Bookings.Booking
  alias Ysc.Repo

  @event_toast "<p>toast body that admin search must not load</p>"
  @post_toast "<p>post HTML that admin search must not load</p>"

  setup do
    user =
      user_fixture(%{
        role: "admin",
        first_name: "SearchTest",
        last_name: "User"
      })

    organizer =
      user_fixture(%{
        first_name: "SearchOrg",
        last_name: "Host"
      })

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

    event =
      event
      |> Ecto.Changeset.change(%{
        raw_details: @event_toast,
        rendered_details: @event_toast
      })
      |> Repo.update!()

    {:ok, post} =
      Posts.create_post(
        %{
          "title" => "Searchable Post Title",
          "preview_text" => "Preview text for search",
          "body" => "Post body",
          "url_name" => "searchable-post-#{System.unique_integer([:positive])}",
          "state" => "published"
        },
        user
      )

    post =
      post
      |> Ecto.Changeset.change(%{
        raw_body: @post_toast,
        rendered_body: @post_toast
      })
      |> Repo.update!()

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
        reference_id: "BK-SEARCH-#{System.unique_integer([:positive])}"
      }
      |> Repo.insert!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    tier = ticket_tier_fixture(%{event_id: event.id})

    ticket =
      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        ticket_tier_id: tier.id,
        user_id: user.id,
        status: :confirmed,
        reference_id: "TKT-SEARCH-#{System.unique_integer([:positive])}",
        expires_at: DateTime.add(now, 1, :day)
      }
      |> Repo.insert!()

    %{
      user: user,
      organizer: organizer,
      event: event,
      post: post,
      booking: booking,
      ticket: ticket
    }
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

    test "finds tickets by reference_id with event title and holder name", %{
      ticket: ticket,
      event: event,
      user: user
    } do
      result = Search.global_search(ticket.reference_id)
      match = Enum.find(result.tickets, &(&1.id == ticket.id))
      assert match
      assert match.event.title == event.title
      assert match.user.first_name == user.first_name
      assert match.user.last_name == user.last_name
      refute Ecto.assoc_loaded?(match.ticket_tier)
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

    test "does not SELECT password hashes, bios, event HTML, post HTML, or ticket tiers",
         %{
           event: event,
           post: post,
           organizer: organizer,
           user: user,
           booking: booking
         } do
      {result, password_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Search.global_search("Searchable Event") end,
          pattern: ~r/hashed_password/i,
          caller_pids: [self()]
        )

      found_event = Enum.find(result.events, &(&1.id == event.id))
      assert found_event
      assert found_event.title == event.title
      assert found_event.reference_id == event.reference_id
      assert found_event.organizer.first_name == organizer.first_name
      assert found_event.organizer.last_name == organizer.last_name
      assert is_nil(found_event.raw_details)
      assert is_nil(found_event.rendered_details)
      assert is_nil(found_event.organizer.hashed_password)
      assert password_cols == 0

      {_result, bio_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Search.global_search("Searchable Event") end,
          pattern: ~r/board_bio/i,
          caller_pids: [self()]
        )

      {_result, event_html_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Search.global_search("Searchable Event") end,
          pattern: ~r/raw_details|rendered_details/i,
          caller_pids: [self()]
        )

      {post_result, post_html_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Search.global_search("Searchable Post") end,
          pattern: ~r/raw_body|rendered_body/i,
          caller_pids: [self()]
        )

      found_post = Enum.find(post_result.posts, &(&1.id == post.id))
      assert found_post
      assert found_post.title == post.title
      assert found_post.author.first_name == user.first_name
      assert is_nil(found_post.raw_body)
      assert is_nil(found_post.rendered_body)

      {_result, ticket_tier_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Search.global_search("Searchable Event") end,
          pattern: ~r/FROM ["']?ticket_tiers["']?/i,
          caller_pids: [self()]
        )

      user_result = Search.global_search("SearchTest")
      found_user = Enum.find(user_result.users, &(&1.id == user.id))
      assert found_user.email == user.email
      assert is_nil(found_user.hashed_password)

      booking_result = Search.global_search(booking.reference_id)
      found_booking = Enum.find(booking_result.bookings, &(&1.id == booking.id))
      assert found_booking.property == :tahoe
      assert found_booking.user.first_name == user.first_name
      assert is_nil(found_booking.pricing_items)

      assert bio_cols == 0
      assert event_html_cols == 0
      assert post_html_cols == 0
      assert ticket_tier_queries == 0
    end
  end

  describe "ci_query_explain_* query builders" do
    test "ci_query_explain_events_query/0 builds an Ecto.Query" do
      assert %Ecto.Query{} = Search.ci_query_explain_events_query()
    end

    test "ci_query_explain_tickets_query/0 builds an Ecto.Query" do
      assert %Ecto.Query{} = Search.ci_query_explain_tickets_query()
    end

    test "ci_query_explain_users_query/0 builds an Ecto.Query" do
      assert %Ecto.Query{} = Search.ci_query_explain_users_query()
    end

    test "ci_query_explain_posts_query/0 builds an Ecto.Query" do
      assert %Ecto.Query{} = Search.ci_query_explain_posts_query()
    end

    test "ci_query_explain_bookings_query/0 builds an Ecto.Query" do
      assert %Ecto.Query{} = Search.ci_query_explain_bookings_query()
    end

    test "ci_query_explain_query/0 delegates to the events query builder" do
      assert %Ecto.Query{} = Search.ci_query_explain_query()
    end
  end
end
