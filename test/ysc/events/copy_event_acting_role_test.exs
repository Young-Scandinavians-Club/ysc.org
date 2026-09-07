defmodule Ysc.Events.CopyEventActingRoleTest do
  @moduledoc """
  Leftover Finding 55 guards: `copy_ticket_tiers: true` must not mint Free /
  $0 / donation inventory when the acting role is volunteer.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Repo

  defp source_with_free_and_donation(user) do
    {:ok, source} =
      Events.create_event(%{
        title: "Finding 55 Override Source",
        description: "Desc",
        state: :published,
        organizer_id: user.id,
        start_date: DateTime.add(DateTime.utc_now(), 30, :day),
        published_at: DateTime.utc_now()
      })

    {:ok, _free} =
      Events.create_ticket_tier(%{
        name: "RSVP",
        type: :free,
        quantity: 50,
        event_id: source.id
      })

    {:ok, _donation} =
      Events.create_ticket_tier(%{
        name: "Support",
        type: :donation,
        quantity: 50,
        event_id: source.id
      })

    Events.get_event!(source.id) |> Repo.preload(:ticket_tiers)
  end

  describe "copy_event/3 volunteer cannot override copy_ticket_tiers" do
    setup do
      %{user: user_fixture()}
    end

    test "ignores copy_ticket_tiers: true when acting_role is volunteer", %{
      user: user
    } do
      source = source_with_free_and_donation(user)

      assert {:ok, copied} =
               Events.copy_event(source, user.id,
                 acting_role: :volunteer,
                 copy_ticket_tiers: true
               )

      copied = Events.get_event!(copied.id) |> Repo.preload(:ticket_tiers)
      assert copied.ticket_tiers == []
    end

    test "ignores copy_ticket_tiers: true when acting_role is the string volunteer",
         %{user: user} do
      source = source_with_free_and_donation(user)

      assert {:ok, copied} =
               Events.copy_event(source, user.id,
                 acting_role: "volunteer",
                 copy_ticket_tiers: true
               )

      copied = Events.get_event!(copied.id) |> Repo.preload(:ticket_tiers)
      assert copied.ticket_tiers == []
    end
  end
end
