defmodule Ysc.Events.TvPosterAlmostFullTest do
  @moduledoc """
  The poster's "Almost Full" badge depends on how many tickets are sold. That
  count must come from the database, not the pricing cache: a stale or
  node-local cache entry would make the Google Photos poster fingerprint flip
  between runs and re-upload the same poster.
  """
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
    event = event_fixture(%{max_attendees: 20})
    tier = ticket_tier_fixture(%{event_id: event.id, quantity: 100})

    %{user: user, event: event, tier: tier}
  end

  defp insert_confirmed(count, ctx) do
    for _ <- 1..count do
      Repo.insert!(%Ticket{
        id: Ecto.ULID.generate(),
        event_id: ctx.event.id,
        user_id: ctx.user.id,
        ticket_tier_id: ctx.tier.id,
        status: :confirmed,
        inserted_at:
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(-1, :day),
        expires_at:
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(1, :day)
      })
    end
  end

  defp poster_event(ctx) do
    Enum.find(Events.list_tv_poster_events(), &(&1.id == ctx.event.id))
  end

  defp poster_hash(ctx), do: ctx |> poster_event() |> TvPosterImage.hash_event()

  test "ticket count is read from the database, not a stale cache entry", ctx do
    EventPricingCache.enrich_event(ctx.event)
    insert_confirmed(17, ctx)

    assert poster_event(ctx).ticket_count == 17

    assert Events.get_event_for_tv_poster(ctx.event.id).ticket_count == 17
  end

  test "poster hash is the same cold, or after the cache was seeded earlier",
       ctx do
    insert_confirmed(17, ctx)

    Cachex.clear(:ysc_cache)
    cold = poster_hash(ctx)

    Cachex.clear(:ysc_cache)
    EventPricingCache.enrich_event(ctx.event)
    seeded_before_sales = poster_hash(ctx)

    assert cold == seeded_before_sales
  end

  test "hash changes when the badge does, and only then", ctx do
    insert_confirmed(5, ctx)
    going_fast = poster_hash(ctx)

    insert_confirmed(1, ctx)
    still_going_fast = poster_hash(ctx)

    insert_confirmed(11, ctx)
    almost_full = poster_hash(ctx)

    assert going_fast == still_going_fast
    assert almost_full != going_fast
  end
end
