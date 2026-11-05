defmodule Ysc.Events.TvPosterSellingFastTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.EventPricingCache
  alias Ysc.Events.Ticket
  alias Ysc.Events.TvPosterImage
  alias Ysc.Repo

  setup do
    EventPricingCache.invalidate()
    Cachex.clear(:ysc_cache)

    user = user_fixture()
    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id})

    %{user: user, event: event, tier: tier}
  end

  defp insert_tickets(count, event, tier, user, opts \\ []) do
    inserted_at =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(Keyword.get(opts, :age_days, -1), :day)

    for _ <- 1..count do
      Repo.insert!(%Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: Keyword.get(opts, :status, :confirmed),
        inserted_at: inserted_at,
        expires_at:
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(1, :day)
      })
    end
  end

  defp poster_event(event_id) do
    Enum.find(Events.list_tv_poster_events(), &(&1.id == event_id))
  end

  test "is selling fast with 5+ recent confirmed tickets", ctx do
    insert_tickets(5, ctx.event, ctx.tier, ctx.user)

    assert poster_event(ctx.event.id).selling_fast
    assert Events.get_event_for_tv_poster(ctx.event.id).selling_fast
  end

  test "is not selling fast with fewer tickets, old tickets or unconfirmed tickets",
       ctx do
    insert_tickets(4, ctx.event, ctx.tier, ctx.user)
    insert_tickets(5, ctx.event, ctx.tier, ctx.user, age_days: -4)
    insert_tickets(5, ctx.event, ctx.tier, ctx.user, status: :pending)

    refute poster_event(ctx.event.id).selling_fast
    refute Events.get_event_for_tv_poster(ctx.event.id).selling_fast
  end

  test "ignores a selling_fast value left in the pricing cache by list traffic",
       ctx do
    EventPricingCache.enrich_event(Map.put(ctx.event, :selling_fast, true))

    refute poster_event(ctx.event.id).selling_fast
    refute Events.get_event_for_tv_poster(ctx.event.id).selling_fast
  end

  test "ignores a missing selling_fast value in the pricing cache", ctx do
    insert_tickets(5, ctx.event, ctx.tier, ctx.user)
    EventPricingCache.enrich_event(ctx.event)

    assert poster_event(ctx.event.id).selling_fast
  end

  test "poster hash is stable whatever the pricing cache holds", ctx do
    insert_tickets(5, ctx.event, ctx.tier, ctx.user)

    hash = fn ->
      ctx.event.id |> poster_event() |> TvPosterImage.hash_event()
    end

    Cachex.clear(:ysc_cache)
    cold = hash.()

    EventPricingCache.enrich_event(Map.put(ctx.event, :selling_fast, false))
    seeded_without = hash.()

    Cachex.clear(:ysc_cache)
    EventPricingCache.enrich_event(Map.put(ctx.event, :selling_fast, true))
    seeded_with = hash.()

    assert cold == seeded_without
    assert cold == seeded_with
  end
end
