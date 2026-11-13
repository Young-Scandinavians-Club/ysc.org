defmodule YscWeb.Emails.NewsletterEditionQueryTest do
  @moduledoc """
  Query-count assertions for newsletter event mapping.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel tests.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Repo
  alias YscWeb.Emails.NewsletterEdition

  @grouped_selling_fast_pattern ~r/FROM "tickets".*GROUP BY/s
  @per_event_selling_fast_pattern ~r/SELECT count\(.*\) FROM "tickets"/i

  defp edition do
    %{title: "Ed", intro_text: "", cover_image: nil}
  end

  defp subscriber do
    %{first_name: "A", email: "a@a.com", subscription_token: "t"}
  end

  defp newsletter_events(events) do
    Enum.map(events, &Repo.preload(&1, [:cover_image, :ticket_tiers]))
  end

  defp insert_recent_tickets(event, count) do
    user = user_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id})

    recent_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(-1, :day)

    for _ <- 1..count do
      Repo.insert!(%Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        inserted_at: recent_time,
        expires_at:
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(1, :day)
      })
    end
  end

  test "maps several internally ticketed events with one grouped selling-fast query" do
    events =
      for _ <- 1..3 do
        event_fixture()
      end
      |> newsletter_events()

    {assigns, grouped} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          NewsletterEdition.build_assigns(edition(), subscriber(), [], events)
        end,
        pattern: @grouped_selling_fast_pattern,
        caller_pids: [self()]
      )

    {_assigns, per_event} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          NewsletterEdition.build_assigns(edition(), subscriber(), [], events)
        end,
        pattern: @per_event_selling_fast_pattern,
        caller_pids: [self()]
      )

    assert grouped == 1
    assert per_event == 0
    assert length(assigns.events) == 3
    assert Enum.all?(assigns.events, &(&1.selling_fast == false))
  end

  test "skips selling-fast queries for externally ticketed events" do
    events =
      for i <- 1..3 do
        event_fixture(%{
          external_ticket_url: "https://tickets.example.org/#{i}",
          external_organizer: "Other Org"
        })
      end
      |> newsletter_events()

    {_assigns, grouped} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          NewsletterEdition.build_assigns(edition(), subscriber(), [], events)
        end,
        pattern: @grouped_selling_fast_pattern,
        caller_pids: [self()]
      )

    {_assigns, tickets} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          NewsletterEdition.build_assigns(edition(), subscriber(), [], events)
        end,
        pattern: ~r/FROM "tickets"/i,
        caller_pids: [self()]
      )

    assert grouped == 0
    assert tickets == 0
  end

  test "personalize/3 does not re-query selling fast" do
    events = newsletter_events([event_fixture(), event_fixture()])

    {assigns_pair, grouped} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          shared = NewsletterEdition.build_shared_assigns(edition(), [], events)

          alice =
            NewsletterEdition.personalize(shared, %{
              first_name: "Alice",
              subscription_token: "a"
            })

          bob =
            NewsletterEdition.personalize(shared, %{
              first_name: "Bob",
              subscription_token: "b"
            })

          {alice, bob}
        end,
        pattern: @grouped_selling_fast_pattern,
        caller_pids: [self()]
      )

    {alice, bob} = assigns_pair
    assert grouped == 1
    assert alice.events == bob.events
    assert alice.first_name == "Alice"
    assert bob.first_name == "Bob"
  end

  test "selling_fast is true when the event recently sold 5+ tickets" do
    event = event_fixture()
    insert_recent_tickets(event, 5)
    events = newsletter_events([event])

    assigns =
      NewsletterEdition.build_assigns(edition(), subscriber(), [], events)

    [mapped] = assigns.events
    assert mapped.selling_fast
    assert Events.event_selling_fast?(event.id)
  end
end
